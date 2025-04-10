-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
--
----
-- PostGIS - Spatial Types for PostgreSQL
-- http://postgis.net
--
-- Copyright (C) 2011 Regina Obe <lr@pcorp.us>
--
-- This is free software; you can redistribute and/or modify it under
-- the terms of the GNU General Public Licence. See the COPYING file.
--
-- Author: Regina Obe <lr@pcorp.us>
--
-- This is a suite of SQL helper functions for use during a PostGIS extension install/upgrade
-- The functions get uninstalled after the extension install/upgrade process
---------------------------
-- postgis_extension_remove_objects: This function removes objects of a particular class from an extension
-- this is needed because there is no ALTER EXTENSION DROP FUNCTION/AGGREGATE command
-- and we can't CREATE OR REPLACE functions whose signatures have changed and we can drop them if they are part of an extension
-- So we use this to remove it from extension first before we drop
CREATE FUNCTION postgis_extension_remove_objects(param_extension text, param_type text)
  RETURNS boolean AS
$$
DECLARE
	var_sql text := '';
	var_r record;
	var_result boolean := false;
	var_class text := '';
	var_is_aggregate boolean := false;
	var_sql_list text := '';
	var_pgsql_version integer := pg_catalog.current_setting('server_version_num');
BEGIN
		var_class := CASE WHEN pg_catalog.lower(param_type) OPERATOR(pg_catalog.=)'function' OR pg_catalog.lower(param_type) OPERATOR(pg_catalog.=) 'aggregate' THEN 'pg_catalog.pg_proc' ELSE '' END;
		var_is_aggregate := CASE WHEN pg_catalog.lower(param_type) OPERATOR(pg_catalog.=) 'aggregate' THEN true ELSE false END;

		IF var_pgsql_version OPERATOR(pg_catalog.<) 110000 THEN
			var_sql_list := $sql$SELECT 'ALTER EXTENSION ' OPERATOR(pg_catalog.||)  e.extname OPERATOR(pg_catalog.||) ' DROP ' OPERATOR(pg_catalog.||) $3 OPERATOR(pg_catalog.||) ' ' OPERATOR(pg_catalog.||) COALESCE(proc.proname OPERATOR(pg_catalog.||) '(' OPERATOR(pg_catalog.||) oidvectortypes(proc.proargtypes) OPERATOR(pg_catalog.||) ')' ,typ.typname, cd.relname, op.oprname,
					cs.typname OPERATOR(pg_catalog.||) ' AS ' OPERATOR(pg_catalog.||) ct.typname OPERATOR(pg_catalog.||) ') ', opcname, opfname) OPERATOR(pg_catalog.||) ';' AS remove_command
			FROM pg_catalog.pg_depend As d INNER JOIN pg_catalog.pg_extension As e
				ON d.refobjid OPERATOR(pg_catalog.=) e.oid INNER JOIN pg_catalog.pg_class As c ON
					c.oid OPERATOR(pg_catalog.=) d.classid
					LEFT JOIN pg_catalog.pg_proc AS proc ON proc.oid OPERATOR(pg_catalog.=) d.objid
					LEFT JOIN pg_catalog.pg_type AS typ ON typ.oid OPERATOR(pg_catalog.=) d.objid
					LEFT JOIN pg_catalog.pg_class As cd ON cd.oid OPERATOR(pg_catalog.=) d.objid
					LEFT JOIN pg_operator As op ON op.oid OPERATOR(pg_catalog.=) d.objid
					LEFT JOIN pg_catalog.pg_cast AS ca ON ca.oid OPERATOR(pg_catalog.=) d.objid
					LEFT JOIN pg_catalog.pg_type AS cs ON ca.castsource OPERATOR(pg_catalog.=) cs.oid
					LEFT JOIN pg_catalog.pg_type AS ct ON ca.casttarget OPERATOR(pg_catalog.=) ct.oid
					LEFT JOIN pg_opclass As oc ON oc.oid OPERATOR(pg_catalog.=) d.objid
					LEFT JOIN pg_opfamily As ofa ON ofa.oid OPERATOR(pg_catalog.=) d.objid
			WHERE d.deptype OPERATOR(pg_catalog.=) 'e' and e.extname OPERATOR(pg_catalog.=) $1 and c.relname OPERATOR(pg_catalog.=) $2 AND COALESCE(proc.proisagg, false) OPERATOR(pg_catalog.=) $4;$sql$;
		ELSE -- for PostgreSQL 11 and above, they removed proc.proisagg among others and replaced with some func type thing
			var_sql_list := $sql$SELECT 'ALTER EXTENSION ' OPERATOR(pg_catalog.||) e.extname OPERATOR(pg_catalog.||) ' DROP ' OPERATOR(pg_catalog.||) $3 OPERATOR(pg_catalog.||) ' ' OPERATOR(pg_catalog.||) COALESCE(proc.proname OPERATOR(pg_catalog.||) '(' OPERATOR(pg_catalog.||) oidvectortypes(proc.proargtypes) OPERATOR(pg_catalog.||) ')' ,typ.typname, cd.relname, op.oprname,
					cs.typname OPERATOR(pg_catalog.||) ' AS ' OPERATOR(pg_catalog.||) ct.typname OPERATOR(pg_catalog.||) ') ', opcname, opfname) OPERATOR(pg_catalog.||) ';' AS remove_command
			FROM pg_catalog.pg_depend As d INNER JOIN pg_catalog.pg_extension As e
				ON d.refobjid OPERATOR(pg_catalog.=) e.oid INNER JOIN pg_catalog.pg_class As c ON
					c.oid OPERATOR(pg_catalog.=) d.classid
					LEFT JOIN pg_catalog.pg_proc AS proc ON proc.oid OPERATOR(pg_catalog.=) d.objid
					LEFT JOIN pg_catalog.pg_type AS typ ON typ.oid OPERATOR(pg_catalog.=) d.objid
					LEFT JOIN pg_catalog.pg_class As cd ON cd.oid OPERATOR(pg_catalog.=) d.objid
					LEFT JOIN pg_operator As op ON op.oid OPERATOR(pg_catalog.=) d.objid
					LEFT JOIN pg_catalog.pg_cast AS ca ON ca.oid OPERATOR(pg_catalog.=) d.objid
					LEFT JOIN pg_catalog.pg_type AS cs ON ca.castsource OPERATOR(pg_catalog.=) cs.oid
					LEFT JOIN pg_catalog.pg_type AS ct ON ca.casttarget OPERATOR(pg_catalog.=) ct.oid
					LEFT JOIN pg_opclass As oc ON oc.oid OPERATOR(pg_catalog.=) d.objid
					LEFT JOIN pg_opfamily As ofa ON ofa.oid OPERATOR(pg_catalog.=) d.objid
			WHERE d.deptype OPERATOR(pg_catalog.=) 'e' and e.extname OPERATOR(pg_catalog.=) $1 and c.relname OPERATOR(pg_catalog.=) $2 AND (proc.prokind OPERATOR(pg_catalog.=) 'a')  OPERATOR(pg_catalog.=) $4;$sql$;
		END IF;

		FOR var_r IN EXECUTE var_sql_list  USING param_extension, var_class, param_type, var_is_aggregate
		LOOP
			var_sql := var_sql OPERATOR(pg_catalog.||) var_r.remove_command OPERATOR(pg_catalog.||) ';';
		END LOOP;
		IF var_sql > '' THEN
			EXECUTE var_sql;
			var_result := true;
		END IF;

		RETURN var_result;
END;
$$
LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION postgis_extension_drop_if_exists(param_extension text, param_statement text)
  RETURNS boolean AS
$$
DECLARE
	var_sql_ext text := 'ALTER EXTENSION ' OPERATOR(pg_catalog.||) pg_catalog.quote_ident(param_extension) OPERATOR(pg_catalog.||) ' ' OPERATOR(pg_catalog.||) pg_catalog.replace(param_statement, 'IF EXISTS', '');
	var_result boolean := false;
BEGIN
	BEGIN
		EXECUTE var_sql_ext;
		var_result := true;
	EXCEPTION
		WHEN OTHERS THEN
			--this is to allow ignoring if the object does not exist in extension
			var_result := false;
	END;
	RETURN var_result;
END;
$$
LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION postgis_extension_AddToSearchPath(a_schema_name text)


RETURNS text
AS
$BODY$
DECLARE
	var_result text;
	var_cur_search_path text;
	a_schema_name text := $1;
BEGIN
	WITH settings AS (
		SELECT unnest(setconfig) config
		FROM pg_db_role_setting
		WHERE setdatabase = (
			SELECT oid
			FROM pg_database
			WHERE datname = current_database()
		) and setrole = 0
	)
	SELECT regexp_replace(config, '^search_path=', '')
	FROM settings WHERE config like 'search_path=%'
	INTO var_cur_search_path;

	RAISE NOTICE 'cur_search_path from pg_db_role_setting is %', var_cur_search_path;

	-- only run this test if person creating the extension is a super user
	IF var_cur_search_path IS NULL AND (SELECT rolsuper FROM pg_roles where rolname = CURRENT_USER) THEN
		SELECT setting
		INTO var_cur_search_path
		FROM pg_file_settings
		WHERE name = 'search_path' AND applied;

		RAISE NOTICE 'cur_search_path from pg_file_settings is %', var_cur_search_path;
	END IF;

	IF var_cur_search_path IS NULL THEN
		SELECT boot_val
		INTO var_cur_search_path
		FROM pg_settings
		WHERE name = 'search_path';

		RAISE NOTICE 'cur_search_path from pg_settings is %', var_cur_search_path;
	END IF;

	IF var_cur_search_path LIKE '%' || quote_ident(a_schema_name) || '%' THEN
		var_result := a_schema_name || ' already in database search_path';
	ELSE
		var_cur_search_path := var_cur_search_path || ', '
                       || quote_ident(a_schema_name);
		EXECUTE 'ALTER DATABASE ' || quote_ident(current_database())
                             || ' SET search_path = ' || var_cur_search_path;
		var_result := a_schema_name || ' has been added to end of database search_path ';
	END IF;

	EXECUTE 'SET search_path = ' || var_cur_search_path;

  RETURN var_result;
END
$BODY$
SET search_path = pg_catalog -- make safe
LANGUAGE 'plpgsql' VOLATILE STRICT
;



-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
--
----
-- PostGIS - Spatial Types for PostgreSQL
-- http://postgis.net
--
-- Copyright (C) 2011 Regina Obe <lr@pcorp.us>
--
-- This is free software; you can redistribute and/or modify it under
-- the terms of the GNU General Public Licence. See the COPYING file.
--
-- Author: Regina Obe <lr@pcorp.us>
--
-- This drops extension helper functions
-- and should be called at the end of the extension upgrade file
-- removes all postgis_topology functions from postgis_topology extension since they will be read
-- during upgrade
SELECT postgis_extension_remove_objects('postgis_tiger_geocoder', 'FUNCTION');
SELECT postgis_extension_remove_objects('postgis_tiger_geocoder', 'AGGREGATE');
 /***
 *
 * Copyright (C) 2012 Regina Obe and Leo Hsu (Paragon Corporation)
 **/
-- Adds a schema to  the front of search path so that functions, tables etc get installed by default in set schema
-- but if people have postgis and other things installed in non-public, it will still keep those in path
-- Example usage: SELECT tiger.SetSearchPathForInstall('tiger');
DROP FUNCTION IF EXISTS tiger.SetSearchPathForInstall(varchar);
CREATE OR REPLACE FUNCTION tiger.SetSearchPathForInstall(a_schema_name text)
RETURNS text
AS
$$
DECLARE
	var_result text;
	var_cur_search_path text;
BEGIN
	SELECT reset_val INTO var_cur_search_path FROM pg_catalog.pg_settings WHERE name = 'search_path';

	EXECUTE 'SET search_path = ' || pg_catalog.quote_ident(a_schema_name) || ', ' || var_cur_search_path;
	var_result := a_schema_name || ' has been made primary for install ';
  RETURN var_result;
END
$$
LANGUAGE 'plpgsql' VOLATILE STRICT;
-- these introduced in PostGIS 2.4
DO language plpgsql
$$
    BEGIN
        ALTER TYPE tiger.norm_addy ADD ATTRIBUTE zip4 varchar;
        ALTER TYPE tiger.norm_addy ADD ATTRIBUTE address_alphanumeric varchar;
    EXCEPTION
        WHEN others THEN  -- ignore the error probably cause it already exists
    END;
$$;--
-- PostGIS - Spatial Types for PostgreSQL
-- http://postgis.net
--
-- Copyright (C) 2010, 2011-2015 Regina Obe and Leo Hsu
--
-- This is free software; you can redistribute and/or modify it under
-- the terms of the GNU General Public Licence. See the COPYING file.
--
-- Author: Regina Obe and Leo Hsu <lr@pcorp.us>
--
-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
--
SELECT tiger.SetSearchPathForInstall('tiger');

CREATE OR REPLACE FUNCTION install_geocode_settings()
	RETURNS void AS
$$
DECLARE var_temp text;
BEGIN
	var_temp := tiger.SetSearchPathForInstall('tiger'); /** set set search path to have tiger in front **/
	IF NOT EXISTS(SELECT table_name FROM information_schema.columns WHERE table_schema = 'tiger' AND table_name = 'geocode_settings')  THEN
		CREATE TABLE geocode_settings(name text primary key, setting text, unit text, category text, short_desc text);
		GRANT SELECT ON geocode_settings TO public;
	END IF;
	IF NOT EXISTS(SELECT table_name FROM information_schema.columns WHERE table_schema = 'tiger' AND table_name = 'geocode_settings_default')  THEN
		CREATE TABLE geocode_settings_default(name text primary key, setting text, unit text, category text, short_desc text);
		GRANT SELECT ON geocode_settings_default TO public;
	END IF;
	--recreate defaults
	TRUNCATE TABLE geocode_settings_default;
	INSERT INTO geocode_settings_default(name,setting,unit,category,short_desc)
		SELECT f.*
		FROM
		(VALUES ('debug_geocode_address', 'false', 'boolean','debug', 'outputs debug information in notice log such as queries when geocode_addresss is called if true')
			, ('debug_geocode_intersection', 'false', 'boolean','debug', 'outputs debug information in notice log such as queries when geocode_intersection is called if true')
			, ('debug_normalize_address', 'false', 'boolean','debug', 'outputs debug information in notice log such as queries and intermediate expressions when normalize_address is called if true')
			, ('debug_reverse_geocode', 'false', 'boolean','debug', 'if true, outputs debug information in notice log such as queries and intermediate expressions when reverse_geocode')
			, ('reverse_geocode_numbered_roads', '0', 'integer','rating', 'For state and county highways, 0 - no preference in name, 1 - prefer the numbered highway name, 2 - prefer local state/county name')
			, ('use_pagc_address_parser', 'false', 'boolean','normalize', 'If set to true, will try to use the address_standardizer extension (via pagc_normalize_address) instead of tiger normalize_address built on')
			, ('zip_penalty', '2', 'numeric','rating', 'As input to rating will add (ref_zip - tar_zip)*zip_penalty where ref_zip is input address and tar_zip is a target address candidate')
		) f(name,setting,unit,category,short_desc);

	-- delete entries that are the same as default values
	DELETE FROM geocode_settings As gc USING geocode_settings_default As gf WHERE gf.name = gc.name AND gf.setting = gc.setting;
END;
$$
language plpgsql;

SELECT install_geocode_settings(); /** create the table if it doesn't exist **/

CREATE OR REPLACE FUNCTION get_geocode_setting(setting_name text)
RETURNS text AS
$$
SELECT COALESCE(gc.setting,gd.setting) As setting FROM geocode_settings_default AS gd LEFT JOIN geocode_settings AS gc ON gd.name = gc.name  WHERE gd.name = $1;
$$
language sql STABLE;

CREATE OR REPLACE FUNCTION set_geocode_setting(setting_name text, setting_value text)
RETURNS text AS
$$
INSERT INTO geocode_settings(name, setting, unit, category, short_desc)
SELECT name, setting, unit, category, short_desc
    FROM geocode_settings_default
    WHERE name NOT IN(SELECT name FROM geocode_settings);

UPDATE geocode_settings SET setting = $2 WHERE name = $1
	RETURNING setting;
$$
language sql VOLATILE;
--
-- PostGIS - Spatial Types for PostgreSQL
-- http://postgis.net
--
-- Copyright (C) 2012-2024 Regina Obe and Leo Hsu
-- Paragon Corporation
--
-- This is free software; you can redistribute and/or modify it under
-- the terms of the GNU General Public Licence. See the COPYING file.
--
-- Author: Regina Obe and Leo Hsu <lr@pcorp.us>
--
-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
SELECT tiger.SetSearchPathForInstall('tiger');

CREATE OR REPLACE FUNCTION create_census_base_tables()
	RETURNS text AS
$$
DECLARE var_temp text;
BEGIN
var_temp := tiger.SetSearchPathForInstall('tiger');
IF NOT EXISTS(SELECT table_name FROM information_schema.columns WHERE table_schema = 'tiger' AND column_name = 'tract_id' AND table_name = 'tract')  THEN
	-- census block group/tracts parent tables not created yet or an older version -- drop old if not in use, create new structure
	DROP TABLE IF EXISTS tiger.tract;
	CREATE TABLE tract
	(
	  gid serial NOT NULL,
	  statefp varchar(2),
	  countyfp varchar(3),
	  tractce varchar(6),
	  tract_id varchar(11) PRIMARY KEY,
	  name varchar(7),
	  namelsad varchar(20),
	  mtfcc varchar(5),
	  funcstat varchar(1),
	  aland double precision,
	  awater double precision,
	  intptlat varchar(11),
	  intptlon varchar(12),
	  the_geom geometry,
	  CONSTRAINT enforce_dims_geom CHECK (st_ndims(the_geom) = 2),
	  CONSTRAINT enforce_geotype_geom CHECK (geometrytype(the_geom) = 'MULTIPOLYGON'::text OR the_geom IS NULL),
	  CONSTRAINT enforce_srid_geom CHECK (st_srid(the_geom) = 4269)
	);

	DROP TABLE IF EXISTS tiger.tabblock;
	CREATE TABLE tabblock
	(
	  gid serial NOT NULL,
	  statefp varchar(2),
	  countyfp varchar(3),
	  tractce varchar(6),
	  blockce varchar(4),
	  tabblock_id varchar(16) PRIMARY KEY,
	  name varchar(20),
	  mtfcc varchar(5),
	  ur varchar(1),
	  uace varchar(5),
	  funcstat varchar(1),
	  aland double precision,
	  awater double precision,
	  intptlat varchar(11),
	  intptlon varchar(12),
	  the_geom geometry,
	  CONSTRAINT enforce_dims_geom CHECK (st_ndims(the_geom) = 2),
	  CONSTRAINT enforce_geotype_geom CHECK (geometrytype(the_geom) = 'MULTIPOLYGON'::text OR the_geom IS NULL),
	  CONSTRAINT enforce_srid_geom CHECK (st_srid(the_geom) = 4269)
	);

	DROP TABLE IF EXISTS tiger.bg;
	CREATE TABLE bg
	(
	  gid serial NOT NULL,
	  statefp varchar(2),
	  countyfp varchar(3),
	  tractce varchar(6),
	  blkgrpce varchar(1),
	  bg_id varchar(12) PRIMARY KEY,
	  namelsad varchar(13),
	  mtfcc varchar(5),
	  funcstat varchar(1),
	  aland double precision,
	  awater double precision,
	  intptlat varchar(11),
	  intptlon varchar(12),
	  the_geom geometry,
	  CONSTRAINT enforce_dims_geom CHECK (st_ndims(the_geom) = 2),
	  CONSTRAINT enforce_geotype_geom CHECK (geometrytype(the_geom) = 'MULTIPOLYGON'::text OR the_geom IS NULL),
	  CONSTRAINT enforce_srid_geom CHECK (st_srid(the_geom) = 4269)
	);
	COMMENT ON TABLE tiger.bg IS 'block groups';
END IF;

IF EXISTS(SELECT * FROM information_schema.columns WHERE table_schema = 'tiger' AND column_name = 'tabblock_id' AND table_name = 'tabblock' AND character_maximum_length < 16)  THEN -- size of name and tabblock_id fields need to be increased
    ALTER TABLE tiger.tabblock ALTER COLUMN name TYPE varchar(20);
    ALTER TABLE tiger.tabblock ALTER COLUMN tabblock_id TYPE varchar(16);
    RAISE NOTICE 'Size of tabblock_id and name are being increased';
END IF;
RETURN 'Tables already present';
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION loader_macro_replace(param_input text, param_keys text[],param_values text[])
RETURNS text AS
$$
	DECLARE var_result text = param_input;
	DECLARE var_count integer = array_upper(param_keys,1);
	BEGIN
		FOR i IN 1..var_count LOOP
			var_result := replace(var_result, '${' || param_keys[i] || '}', param_values[i]);
		END LOOP;
		return var_result;
	END;
$$
  LANGUAGE 'plpgsql' IMMUTABLE
  COST 100;

CREATE TABLE IF NOT EXISTS tiger.tabblock20
(
    statefp character varying(2) ,
    countyfp character varying(3) ,
    tractce character varying(6) ,
    blockce character varying(4) ,
    geoid character varying(15) ,
    name character varying(10) ,
    mtfcc character varying(5) ,
    ur character varying(1) ,
    uace character varying(5) ,
    uatype character varying(1) ,
    funcstat character varying(1) ,
    aland double precision,
    awater double precision,
    intptlat character varying(11) ,
    intptlon character varying(12) ,
    the_geom geometry(MultiPolygon,4269), housing float, pop float,
    CONSTRAINT pk_tabblock20 PRIMARY KEY (geoid)
);

ALTER TABLE tiger.faces ADD IF NOT EXISTS tractce20 varchar(6);
ALTER TABLE tiger.faces ADD IF NOT EXISTS blkgrpce20 varchar(1);
ALTER TABLE tiger.faces ADD IF NOT EXISTS blockce20  varchar(4);
ALTER TABLE tiger.faces ADD IF NOT EXISTS countyfp20 varchar(3);
ALTER TABLE tiger.faces ADD IF NOT EXISTS statefp20 varchar(2);

ALTER TABLE tiger.tabblock20 ADD IF NOT EXISTS housing float;
ALTER TABLE tiger.tabblock20 ADD IF NOT EXISTS pop float;


-- Helper function that generates script to drop all tables in a particular schema for a particular table
-- This is useful in case you need to reload a state
CREATE OR REPLACE FUNCTION drop_state_tables_generate_script(param_state text, param_schema text DEFAULT 'tiger_data')
  RETURNS text AS
$$
SELECT array_to_string(array_agg('DROP TABLE ' || quote_ident(table_schema) || '.' || quote_ident(table_name) || ';'),E'\n')
	FROM (SELECT * FROM information_schema.tables
	WHERE table_schema = $2 AND table_name like lower($1) || '~_%' ESCAPE '~' ORDER BY table_name) AS foo;
;
$$
  LANGUAGE sql VOLATILE;

-- Helper function that generates script to drop all nation tables (county, state) in a particular schema
-- This is useful for loading 2011 because state and county tables aren't broken out into separate state files
DROP FUNCTION IF EXISTS drop_national_tables_generate_script(text);
CREATE OR REPLACE FUNCTION drop_nation_tables_generate_script(param_schema text DEFAULT 'tiger_data')
  RETURNS text AS
$$
SELECT array_to_string(array_agg('DROP TABLE ' || quote_ident(table_schema) || '.' || quote_ident(table_name) || ';'),E'\n')
	FROM (SELECT * FROM information_schema.tables
	WHERE table_schema = $1 AND (table_name ~ E'^[a-z]{2}\_county' or table_name ~ E'^[a-z]{2}\_state' or table_name = 'state_all' or table_name LIKE 'county_all%' or table_name LIKE 'zcta5_all%') ORDER BY table_name) AS foo;
;
$$
  LANGUAGE sql VOLATILE;

DO
$$
BEGIN
  IF NOT EXISTS (SELECT * FROM information_schema.tables WHERE table_name = 'loader_platform' AND table_schema = 'tiger') THEN
      CREATE TABLE loader_platform(os varchar(50) PRIMARY KEY, declare_sect text, pgbin text, wget text, unzip_command text, psql text, path_sep text, loader text, environ_set_command text, county_process_command text);
  END IF;
END
$$ LANGUAGE 'plpgsql';

DO
$$
BEGIN
  IF NOT EXISTS (SELECT * FROM information_schema.schemata WHERE schema_name = 'tiger_data') THEN
       CREATE SCHEMA tiger_data;
  END IF;
END
$$ LANGUAGE 'plpgsql';

DELETE FROM loader_platform WHERE os IN ('sh', 'windows');
GRANT SELECT ON TABLE loader_platform TO public;
INSERT INTO loader_platform(os, wget, pgbin, declare_sect, unzip_command, psql,path_sep,loader, environ_set_command, county_process_command)
VALUES('windows', '%WGETTOOL%', '%PGBIN%',
E'set TMPDIR=${staging_fold}\\temp\\
set UNZIPTOOL="C:\\Program Files\\7-Zip\\7z.exe"
set WGETTOOL="C:\\wget\\wget.exe"
set PGBIN=C:\\Program Files\\PostgreSQL\\17\\bin\\
set PGPORT=5432
set PGHOST=localhost
set PGUSER=postgres
set PGPASSWORD=yourpasswordhere
set PGDATABASE=geocoder
set PSQL="%PGBIN%psql"
set SHP2PGSQL="%PGBIN%shp2pgsql"
cd ${staging_fold}
', E'del %TMPDIR%\\*.* /Q
%PSQL% -c "DROP SCHEMA IF EXISTS ${staging_schema} CASCADE;"
%PSQL% -c "CREATE SCHEMA ${staging_schema};"
%PSQL% -c "DO language ''plpgsql'' $$ BEGIN IF NOT EXISTS (SELECT * FROM information_schema.schemata WHERE schema_name = ''${data_schema}'' ) THEN CREATE SCHEMA ${data_schema}; END IF;  END $$"
for /r %%z in (*.zip) do %UNZIPTOOL% e %%z  -o%TMPDIR%
cd %TMPDIR%', E'%PSQL%', E'\\', E'%SHP2PGSQL%', 'set ',
'for /r %%z in (*${table_name}*.dbf) do (${loader} -D -s 4269 -g the_geom -W "latin1" %%z tiger_staging.${state_abbrev}_${table_name} | ${psql} & ${psql} -c "SELECT loader_load_staged_data(lower(''${state_abbrev}_${table_name}''), lower(''${state_abbrev}_${lookup_name}''));")'
);

INSERT INTO loader_platform(os, wget, pgbin, declare_sect, unzip_command, psql, path_sep, loader, environ_set_command, county_process_command)
VALUES('sh', 'wget', '',
E'TMPDIR="${staging_fold}/temp/"
UNZIPTOOL=unzip
WGETTOOL="/usr/bin/wget"
export PGBIN=/usr/lib/postgresql/17/bin
export PGPORT=5432
export PGHOST=localhost
export PGUSER=postgres
export PGPASSWORD=yourpasswordhere
export PGDATABASE=geocoder
PSQL=${PGBIN}/psql
SHP2PGSQL=shp2pgsql
cd ${staging_fold}
', E'rm -f ${TMPDIR}/*.*
${PSQL} -c "DROP SCHEMA IF EXISTS ${staging_schema} CASCADE;"
${PSQL} -c "CREATE SCHEMA ${staging_schema};"
for z in *.zip; do $UNZIPTOOL -o -d $TMPDIR $z; done
cd $TMPDIR;\n', '${PSQL}', '/', '${SHP2PGSQL}', 'export ',
'for z in *${table_name}*.dbf; do
${loader} -D -s 4269 -g the_geom -W "latin1" $z ${staging_schema}.${state_abbrev}_${table_name} | ${psql}
${PSQL} -c "SELECT loader_load_staged_data(lower(''${state_abbrev}_${table_name}''), lower(''${state_abbrev}_${lookup_name}''));"
done');

-- variables table
DO $$
BEGIN
  IF NOT EXISTS (SELECT * FROM information_schema.tables WHERE table_name = 'loader_variables' AND table_schema = 'tiger') THEN
      CREATE TABLE loader_variables(tiger_year varchar(4) PRIMARY KEY, website_root text, staging_fold text, data_schema text, staging_schema text);
  END IF;
END
$$ LANGUAGE 'plpgsql';

TRUNCATE TABLE loader_variables;
INSERT INTO loader_variables(tiger_year, website_root , staging_fold, data_schema, staging_schema)
	VALUES('2024', 'https://www2.census.gov/geo/tiger/TIGER2024', '/gisdata', 'tiger_data', 'tiger_staging');
GRANT SELECT ON TABLE loader_variables TO public;

DO $$
BEGIN
  IF NOT EXISTS (SELECT * FROM information_schema.tables WHERE table_name = 'loader_lookuptables' AND table_schema = 'tiger') THEN
   CREATE TABLE loader_lookuptables(process_order integer NOT NULL DEFAULT 1000,
		lookup_name text primary key,
		table_name text, single_mode boolean NOT NULL DEFAULT true,
		load boolean NOT NULL DEFAULT true,
		level_county boolean NOT NULL DEFAULT false,
		level_state boolean NOT NULL DEFAULT false,
		level_nation boolean NOT NULL DEFAULT false,
		post_load_process text, single_geom_mode boolean DEFAULT false,
		insert_mode char(1) NOT NULL DEFAULT 'c',
		pre_load_process text,columns_exclude text[], website_root_override text);
  END IF;
END
$$ LANGUAGE 'plpgsql';

TRUNCATE TABLE loader_lookuptables;

GRANT SELECT ON TABLE loader_lookuptables TO public;

-- put in explanatory comments of what each column is for
COMMENT ON COLUMN loader_lookuptables.lookup_name IS 'This is the table name to inherit from and suffix of resulting output table -- how the table will be named --  edges here would mean -- ma_edges , pa_edges etc. except in the case of national tables. national level tables have no prefix';
COMMENT ON COLUMN loader_lookuptables.level_nation IS 'These are tables that contain all data for the whole US so there is just a single file';
COMMENT ON COLUMN loader_lookuptables.table_name IS 'suffix of the tables to load e.g.  edges would load all tables like *edges.dbf(shp)  -- so tl_2010_42129_edges.dbf .  ';
COMMENT ON COLUMN loader_lookuptables.load IS 'Whether or not to load the table.  For states and zcta5 (you may just want to download states10, zcta510 nationwide file manually) load your own into a single table that inherits from tiger.states, tiger.zcta5.  You''ll get improved performance for some geocoding cases.';
COMMENT ON COLUMN loader_lookuptables.columns_exclude IS 'List of columns to exclude as an array. This is excluded from both input table and output table and rest of columns remaining are assumed to be in same order in both tables. gid, geoid,cpi,suffix1ce are excluded if no columns are specified.';
COMMENT ON COLUMN loader_lookuptables.website_root_override IS 'Path to use for wget instead of that specified in year table.  Needed currently for zcta where they release that only for 2000 and 2010';

INSERT INTO loader_lookuptables(process_order, lookup_name, table_name, load, level_county, level_state, single_geom_mode, insert_mode, pre_load_process, post_load_process, columns_exclude )
VALUES(10, 'tract', 'tract', true, false, true,false, 'c',
'${psql} -c "CREATE TABLE ${data_schema}.${state_abbrev}_${lookup_name}(CONSTRAINT pk_${state_abbrev}_${lookup_name} PRIMARY KEY (tract_id) ) INHERITS(tiger.${lookup_name}); " ',
	'${psql} -c "ALTER TABLE ${staging_schema}.${state_abbrev}_${table_name} RENAME geoid TO tract_id; SELECT loader_load_staged_data(lower(''${state_abbrev}_${table_name}''), lower(''${state_abbrev}_${lookup_name}'')); "
	${psql} -c "CREATE INDEX ${data_schema}_${state_abbrev}_${lookup_name}_the_geom_gist ON ${data_schema}.${state_abbrev}_${lookup_name} USING gist(the_geom);"
	${psql} -c "VACUUM ANALYZE ${data_schema}.${state_abbrev}_${lookup_name};"
	${psql} -c "ALTER TABLE ${data_schema}.${state_abbrev}_${lookup_name} ADD CONSTRAINT chk_statefp CHECK (statefp = ''${state_fips}'');"', ARRAY['gid', 'geoidfq']);

INSERT INTO loader_lookuptables(process_order, lookup_name, table_name, load, level_county, level_state, single_geom_mode, insert_mode, pre_load_process, post_load_process, columns_exclude )
VALUES(11, 'tabblock20', 'tabblock20', true, false, true,false, 'c',
'${psql} -c "CREATE TABLE ${data_schema}.${state_abbrev}_${lookup_name}(CONSTRAINT pk_${state_abbrev}_${lookup_name} PRIMARY KEY (geoid)) INHERITS(tiger.${lookup_name});" ',
'${psql} -c "SELECT loader_load_staged_data(lower(''${state_abbrev}_${table_name}''), lower(''${state_abbrev}_${lookup_name}'')); "
${psql} -c "ALTER TABLE ${data_schema}.${state_abbrev}_${lookup_name} ADD CONSTRAINT chk_statefp CHECK (statefp = ''${state_fips}'');"
${psql} -c "CREATE INDEX ${data_schema}_${state_abbrev}_${lookup_name}_the_geom_gist ON ${data_schema}.${state_abbrev}_${lookup_name} USING gist(the_geom);"
${psql} -c "vacuum analyze ${data_schema}.${state_abbrev}_${lookup_name};"', '{gid, geoidfq20, uatype}'::text[]);

INSERT INTO loader_lookuptables(process_order, lookup_name, table_name, load, level_county, level_state, single_geom_mode, insert_mode, pre_load_process, post_load_process, columns_exclude )
VALUES(12, 'bg', 'bg', false,false, true,false, 'c',
'${psql} -c "CREATE TABLE ${data_schema}.${state_abbrev}_${lookup_name}(CONSTRAINT pk_${state_abbrev}_${lookup_name} PRIMARY KEY (bg_id)) INHERITS(tiger.${lookup_name});" ',
'${psql} -c "ALTER TABLE ${staging_schema}.${state_abbrev}_${table_name} RENAME geoid TO bg_id;  SELECT loader_load_staged_data(lower(''${state_abbrev}_${table_name}''), lower(''${state_abbrev}_${lookup_name}'')); "
${psql} -c "ALTER TABLE ${data_schema}.${state_abbrev}_${lookup_name} ADD CONSTRAINT chk_statefp CHECK (statefp = ''${state_fips}'');"
${psql} -c "CREATE INDEX ${data_schema}_${state_abbrev}_${lookup_name}_the_geom_gist ON ${data_schema}.${state_abbrev}_${lookup_name} USING gist(the_geom);"
${psql} -c "vacuum analyze ${data_schema}.${state_abbrev}_${lookup_name};"', ARRAY['gid', 'geoidfq']);

INSERT INTO loader_lookuptables(process_order, lookup_name, table_name, load, level_county, level_state,  level_nation, single_geom_mode, pre_load_process, post_load_process)
VALUES(2, 'county_all', 'county', true, false, false, true,
	false, '${psql} -c "CREATE TABLE ${data_schema}.${lookup_name}(CONSTRAINT pk_${data_schema}_${lookup_name} PRIMARY KEY (cntyidfp),CONSTRAINT uidx_${data_schema}_${lookup_name}_gid UNIQUE (gid)  ) INHERITS(tiger.county); " ',
	'${psql} -c "ALTER TABLE ${staging_schema}.${table_name} RENAME geoid TO cntyidfp;  SELECT loader_load_staged_data(lower(''${table_name}''), lower(''${lookup_name}''));"
	${psql} -c "CREATE INDEX ${data_schema}_${table_name}_the_geom_gist ON ${data_schema}.${lookup_name} USING gist(the_geom);"
	${psql} -c "CREATE UNIQUE INDEX uidx_${data_schema}_${lookup_name}_statefp_countyfp ON ${data_schema}.${lookup_name} USING btree(statefp,countyfp);"
	${psql} -c "CREATE TABLE ${data_schema}.${lookup_name}_lookup ( CONSTRAINT pk_${lookup_name}_lookup PRIMARY KEY (st_code, co_code)) INHERITS (tiger.county_lookup);"
	${psql} -c "VACUUM ANALYZE ${data_schema}.${lookup_name};"
	${psql} -c "INSERT INTO ${data_schema}.${lookup_name}_lookup(st_code, state, co_code, name) SELECT CAST(s.statefp as integer), s.abbrev, CAST(c.countyfp as integer), c.name FROM ${data_schema}.${lookup_name} As c INNER JOIN state_lookup As s ON s.statefp = c.statefp;"
	${psql} -c "VACUUM ANALYZE ${data_schema}.${lookup_name}_lookup;" ');

INSERT INTO loader_lookuptables(process_order, lookup_name, table_name, load, level_county, level_state, level_nation, single_geom_mode, insert_mode, pre_load_process, post_load_process )
VALUES(1, 'state_all', 'state', true, false, false,true,false, 'c',
	'${psql} -c "CREATE TABLE ${data_schema}.${lookup_name}(CONSTRAINT pk_${lookup_name} PRIMARY KEY (statefp),CONSTRAINT uidx_${lookup_name}_stusps  UNIQUE (stusps), CONSTRAINT uidx_${lookup_name}_gid UNIQUE (gid) ) INHERITS(tiger.state); "',
	'${psql} -c "SELECT loader_load_staged_data(lower(''${table_name}''), lower(''${lookup_name}'')); "
	${psql} -c "CREATE INDEX ${data_schema}_${lookup_name}_the_geom_gist ON ${data_schema}.${lookup_name} USING gist(the_geom);"
	${psql} -c "VACUUM ANALYZE ${data_schema}.${lookup_name}"' );

INSERT INTO loader_lookuptables(process_order, lookup_name, table_name, load, level_county, level_state, single_geom_mode, insert_mode, pre_load_process, post_load_process )
VALUES(3, 'place', 'place', true, false, true,false, 'c',
	'${psql} -c "CREATE TABLE ${data_schema}.${state_abbrev}_${lookup_name}(CONSTRAINT pk_${state_abbrev}_${table_name} PRIMARY KEY (plcidfp) ) INHERITS(tiger.place);" ',
	'${psql} -c "ALTER TABLE ${staging_schema}.${state_abbrev}_${table_name} RENAME geoid TO plcidfp;SELECT loader_load_staged_data(lower(''${state_abbrev}_${table_name}''), lower(''${state_abbrev}_${lookup_name}'')); ALTER TABLE ${data_schema}.${state_abbrev}_${lookup_name} ADD CONSTRAINT uidx_${state_abbrev}_${lookup_name}_gid UNIQUE (gid);"
${psql} -c "CREATE INDEX idx_${state_abbrev}_${lookup_name}_soundex_name ON ${data_schema}.${state_abbrev}_${lookup_name} USING btree (soundex(name));"
${psql} -c "CREATE INDEX ${data_schema}_${state_abbrev}_${lookup_name}_the_geom_gist ON ${data_schema}.${state_abbrev}_${lookup_name} USING gist(the_geom);"
${psql} -c "ALTER TABLE ${data_schema}.${state_abbrev}_${lookup_name} ADD CONSTRAINT chk_statefp CHECK (statefp = ''${state_fips}'');"'
	);

INSERT INTO loader_lookuptables(process_order, lookup_name, table_name, load, level_county, level_state, single_geom_mode, insert_mode, pre_load_process, post_load_process )
VALUES(4, 'cousub', 'cousub', true, false, true,false, 'c',
	'${psql} -c "CREATE TABLE ${data_schema}.${state_abbrev}_${lookup_name}(CONSTRAINT pk_${state_abbrev}_${lookup_name} PRIMARY KEY (cosbidfp), CONSTRAINT uidx_${state_abbrev}_${lookup_name}_gid UNIQUE (gid)) INHERITS(tiger.${lookup_name});" ',
	'${psql} -c "ALTER TABLE ${staging_schema}.${state_abbrev}_${table_name} RENAME geoid TO cosbidfp;SELECT loader_load_staged_data(lower(''${state_abbrev}_${table_name}''), lower(''${state_abbrev}_${lookup_name}'')); ALTER TABLE ${data_schema}.${state_abbrev}_${lookup_name} ADD CONSTRAINT chk_statefp CHECK (statefp = ''${state_fips}'');"
${psql} -c "CREATE INDEX ${data_schema}_${state_abbrev}_${lookup_name}_the_geom_gist ON ${data_schema}.${state_abbrev}_${lookup_name} USING gist(the_geom);"
${psql} -c "CREATE INDEX idx_${data_schema}_${state_abbrev}_${lookup_name}_countyfp ON ${data_schema}.${state_abbrev}_${lookup_name} USING btree(countyfp);"');

INSERT INTO loader_lookuptables(process_order, lookup_name, table_name, load, level_county, level_state, level_nation, single_geom_mode, insert_mode, pre_load_process, post_load_process, columns_exclude )
VALUES(13, 'zcta5_raw', 'zcta520', false,false, false,true, false, 'c',
	'${psql} -c "CREATE TABLE ${data_schema}.${lookup_name}( zcta5 character varying(5), classfp character varying(2),mtfcc character varying(5), funcstat character varying(1), aland double precision, awater double precision, intptlat character varying(11), intptlon character varying(12), the_geom geometry(MultiPolygon,4269) );"',
$post_load$${psql} -c "ALTER TABLE tiger.zcta5 DROP CONSTRAINT IF EXISTS enforce_geotype_the_geom; CREATE TABLE ${data_schema}.zcta5_all(CONSTRAINT pk_zcta5_all PRIMARY KEY (zcta5ce,statefp), CONSTRAINT uidx_${lookup_name}_all_gid UNIQUE (gid)) INHERITS(tiger.zcta5);"
${psql} -c "SELECT loader_load_staged_data(lower('${table_name}'), lower('${lookup_name}'));"
${psql} -c "INSERT INTO ${data_schema}.zcta5_all(statefp, zcta5ce, classfp, mtfcc, funcstat, aland, awater, intptlat, intptlon, partflg, the_geom) SELECT  s.statefp, z.zcta5,  z.classfp, z.mtfcc, z.funcstat, z.aland, z.awater, z.intptlat, z.intptlon, CASE WHEN ST_Covers(s.the_geom, z.the_geom) THEN 'N' ELSE 'Y' END, ST_SnapToGrid(ST_Transform(CASE WHEN ST_Covers(s.the_geom, z.the_geom) THEN ST_SimplifyPreserveTopology(ST_Transform(z.the_geom,2163),1000) ELSE ST_SimplifyPreserveTopology(ST_Intersection(ST_Transform(s.the_geom,2163), ST_Transform(z.the_geom,2163)),1000)  END,4269), 0.000001) As geom FROM ${data_schema}.zcta5_raw AS z INNER JOIN tiger.state AS s ON (ST_Covers(s.the_geom, z.the_geom) or ST_Overlaps(s.the_geom, z.the_geom) );"
	${psql} -c "DROP TABLE ${data_schema}.zcta5_raw; CREATE INDEX idx_${data_schema}_zcta5_all_the_geom_gist ON ${data_schema}.zcta5_all USING gist(the_geom);"$post_load$
, ARRAY['gid','geoid','geoid10', 'geoid20', 'geoidfq20', 'partflg']);

INSERT INTO loader_lookuptables(process_order, lookup_name, table_name, load, level_county, level_state, single_geom_mode, insert_mode, pre_load_process, post_load_process, columns_exclude )
VALUES(6, 'faces', 'faces', true, true, false,false, 'c',
	'${psql} -c "CREATE TABLE ${data_schema}.${state_abbrev}_${table_name}(CONSTRAINT pk_${state_abbrev}_${lookup_name} PRIMARY KEY (gid)) INHERITS(tiger.${lookup_name});" ',
	'${psql} -c "CREATE INDEX ${data_schema}_${state_abbrev}_${table_name}_the_geom_gist ON ${data_schema}.${state_abbrev}_${lookup_name} USING gist(the_geom);"
	${psql} -c "CREATE INDEX idx_${data_schema}_${state_abbrev}_${lookup_name}_tfid ON ${data_schema}.${state_abbrev}_${lookup_name} USING btree (tfid);"
	${psql} -c "CREATE INDEX idx_${data_schema}_${state_abbrev}_${table_name}_countyfp ON ${data_schema}.${state_abbrev}_${table_name} USING btree (countyfp);"
	${psql} -c "ALTER TABLE ${data_schema}.${state_abbrev}_${lookup_name} ADD CONSTRAINT chk_statefp CHECK (statefp = ''${state_fips}'');"
	${psql} -c "vacuum analyze ${data_schema}.${state_abbrev}_${lookup_name};"', ARRAY['gid', 'geoid','geoidfq', 'cpi','suffix1ce', 'statefp00', 'statefp10', 'countyfp00','countyfp10'
   ,'tractce00','tractce10', 'blkgrpce00', 'blkgrpce10', 'blockce00', 'blockce10'
      , 'cousubfp00', 'submcdfp00', 'conctyfp00', 'placefp00', 'aiannhfp00', 'aiannhce00',
       'comptyp00', 'trsubfp00', 'trsubce00', 'anrcfp00', 'elsdlea00', 'scsdlea00',
       'unsdlea00', 'uace00', 'cd108fp', 'sldust00', 'sldlst00', 'vtdst00', 'zcta5ce00',
       'tazce00', 'ugace00', 'puma5ce00','vtdst10','tazce10','uace10','puma5ce10','tazce', 'uace', 'vtdst',  'zcta5ce10', 'puma5ce', 'ugace10','pumace10', 'estatefp', 'ugace', 'blockce', 'pumace20', 'sdadmlea', 'uace20', 'cnectafp', 'nctadvfp','nectafp']);
INSERT INTO loader_lookuptables(process_order, lookup_name, table_name, load, level_county, level_state, single_geom_mode, insert_mode, pre_load_process, post_load_process, columns_exclude )
VALUES(7, 'featnames', 'featnames', true, true, false,false, 'a',
'${psql} -c "CREATE TABLE ${data_schema}.${state_abbrev}_${table_name}(CONSTRAINT pk_${state_abbrev}_${table_name} PRIMARY KEY (gid)) INHERITS(tiger.${table_name});ALTER TABLE ${data_schema}.${state_abbrev}_${table_name} ALTER COLUMN statefp SET DEFAULT ''${state_fips}'';" ',
'${psql} -c "CREATE INDEX idx_${data_schema}_${state_abbrev}_${lookup_name}_snd_name ON ${data_schema}.${state_abbrev}_${table_name} USING btree (soundex(name));"
${psql} -c "CREATE INDEX idx_${data_schema}_${state_abbrev}_${lookup_name}_lname ON ${data_schema}.${state_abbrev}_${table_name} USING btree (lower(name));"
${psql} -c "CREATE INDEX idx_${data_schema}_${state_abbrev}_${lookup_name}_tlid_statefp ON ${data_schema}.${state_abbrev}_${table_name} USING btree (tlid,statefp);"
${psql} -c "ALTER TABLE ${data_schema}.${state_abbrev}_${lookup_name} ADD CONSTRAINT chk_statefp CHECK (statefp = ''${state_fips}'');"
${psql} -c "vacuum analyze ${data_schema}.${state_abbrev}_${lookup_name};"', ARRAY['gid','statefp', 'geoidfq']);

INSERT INTO loader_lookuptables(process_order, lookup_name, table_name, load, level_county, level_state, single_geom_mode, insert_mode, pre_load_process, post_load_process, columns_exclude )
VALUES(8, 'edges', 'edges', true, true, false,false, 'a',
'${psql} -c "CREATE TABLE ${data_schema}.${state_abbrev}_${table_name}(CONSTRAINT pk_${state_abbrev}_${table_name} PRIMARY KEY (gid)) INHERITS(tiger.${table_name});"',
'${psql} -c "ALTER TABLE ${data_schema}.${state_abbrev}_${table_name} ADD CONSTRAINT chk_statefp CHECK (statefp = ''${state_fips}'');"
${psql} -c "CREATE INDEX idx_${data_schema}_${state_abbrev}_${lookup_name}_tlid ON ${data_schema}.${state_abbrev}_${table_name} USING btree (tlid);"
${psql} -c "CREATE INDEX idx_${data_schema}_${state_abbrev}_${lookup_name}tfidr ON ${data_schema}.${state_abbrev}_${table_name} USING btree (tfidr);"
${psql} -c "CREATE INDEX idx_${data_schema}_${state_abbrev}_${lookup_name}_tfidl ON ${data_schema}.${state_abbrev}_${table_name} USING btree (tfidl);"
${psql} -c "CREATE INDEX idx_${data_schema}_${state_abbrev}_${lookup_name}_countyfp ON ${data_schema}.${state_abbrev}_${table_name} USING btree (countyfp);"
${psql} -c "CREATE INDEX ${data_schema}_${state_abbrev}_${table_name}_the_geom_gist ON ${data_schema}.${state_abbrev}_${table_name} USING gist(the_geom);"
${psql} -c "CREATE INDEX idx_${data_schema}_${state_abbrev}_${lookup_name}_zipl ON ${data_schema}.${state_abbrev}_${lookup_name} USING btree (zipl);"
${psql} -c "CREATE TABLE ${data_schema}.${state_abbrev}_zip_state_loc(CONSTRAINT pk_${state_abbrev}_zip_state_loc PRIMARY KEY(zip,stusps,place)) INHERITS(tiger.zip_state_loc);"
${psql} -c "INSERT INTO ${data_schema}.${state_abbrev}_zip_state_loc(zip,stusps,statefp,place) SELECT DISTINCT e.zipl, ''${state_abbrev}'', ''${state_fips}'', p.name FROM ${data_schema}.${state_abbrev}_edges AS e INNER JOIN ${data_schema}.${state_abbrev}_faces AS f ON (e.tfidl = f.tfid OR e.tfidr = f.tfid) INNER JOIN ${data_schema}.${state_abbrev}_place As p ON(f.statefp = p.statefp AND f.placefp = p.placefp ) WHERE e.zipl IS NOT NULL;"
${psql} -c "CREATE INDEX idx_${data_schema}_${state_abbrev}_zip_state_loc_place ON ${data_schema}.${state_abbrev}_zip_state_loc USING btree(soundex(place));"
${psql} -c "ALTER TABLE ${data_schema}.${state_abbrev}_zip_state_loc ADD CONSTRAINT chk_statefp CHECK (statefp = ''${state_fips}'');"
${psql} -c "vacuum analyze ${data_schema}.${state_abbrev}_${lookup_name};"
${psql} -c "vacuum analyze ${data_schema}.${state_abbrev}_zip_state_loc;"
${psql} -c "CREATE TABLE ${data_schema}.${state_abbrev}_zip_lookup_base(CONSTRAINT pk_${state_abbrev}_zip_state_loc_city PRIMARY KEY(zip,state, county, city, statefp)) INHERITS(tiger.zip_lookup_base);"
${psql} -c "INSERT INTO ${data_schema}.${state_abbrev}_zip_lookup_base(zip,state,county,city, statefp) SELECT DISTINCT e.zipl, ''${state_abbrev}'', c.name,p.name,''${state_fips}''  FROM ${data_schema}.${state_abbrev}_edges AS e INNER JOIN tiger.county As c  ON (e.countyfp = c.countyfp AND e.statefp = c.statefp AND e.statefp = ''${state_fips}'') INNER JOIN ${data_schema}.${state_abbrev}_faces AS f ON (e.tfidl = f.tfid OR e.tfidr = f.tfid) INNER JOIN ${data_schema}.${state_abbrev}_place As p ON(f.statefp = p.statefp AND f.placefp = p.placefp ) WHERE e.zipl IS NOT NULL;"
${psql} -c "ALTER TABLE ${data_schema}.${state_abbrev}_zip_lookup_base ADD CONSTRAINT chk_statefp CHECK (statefp = ''${state_fips}'');"
${psql} -c "CREATE INDEX idx_${data_schema}_${state_abbrev}_zip_lookup_base_citysnd ON ${data_schema}.${state_abbrev}_zip_lookup_base USING btree(soundex(city));"',  ARRAY['gid', 'geoid', 'geoidfq', 'divroad'] );

INSERT INTO loader_lookuptables(process_order, lookup_name, table_name, load, level_county, level_state, single_geom_mode, insert_mode, pre_load_process, post_load_process,columns_exclude )
VALUES(9, 'addr', 'addr', true, true, false,false, 'a',
	'${psql} -c "CREATE TABLE ${data_schema}.${state_abbrev}_${lookup_name}(CONSTRAINT pk_${state_abbrev}_${table_name} PRIMARY KEY (gid)) INHERITS(tiger.${table_name});ALTER TABLE ${data_schema}.${state_abbrev}_${lookup_name} ALTER COLUMN statefp SET DEFAULT ''${state_fips}'';" ',
	'${psql} -c "ALTER TABLE ${data_schema}.${state_abbrev}_${lookup_name} ADD CONSTRAINT chk_statefp CHECK (statefp = ''${state_fips}'');"
	${psql} -c "CREATE INDEX idx_${data_schema}_${state_abbrev}_${lookup_name}_least_address ON tiger_data.${state_abbrev}_addr USING btree (least_hn(fromhn,tohn) );"
	${psql} -c "CREATE INDEX idx_${data_schema}_${state_abbrev}_${table_name}_tlid_statefp ON ${data_schema}.${state_abbrev}_${table_name} USING btree (tlid, statefp);"
	${psql} -c "CREATE INDEX idx_${data_schema}_${state_abbrev}_${table_name}_zip ON ${data_schema}.${state_abbrev}_${table_name} USING btree (zip);"
	${psql} -c "CREATE TABLE ${data_schema}.${state_abbrev}_zip_state(CONSTRAINT pk_${state_abbrev}_zip_state PRIMARY KEY(zip,stusps)) INHERITS(tiger.zip_state); "
	${psql} -c "INSERT INTO ${data_schema}.${state_abbrev}_zip_state(zip,stusps,statefp) SELECT DISTINCT zip, ''${state_abbrev}'', ''${state_fips}'' FROM ${data_schema}.${state_abbrev}_${lookup_name} WHERE zip is not null;"
	${psql} -c "ALTER TABLE ${data_schema}.${state_abbrev}_zip_state ADD CONSTRAINT chk_statefp CHECK (statefp = ''${state_fips}'');"
	${psql} -c "vacuum analyze ${data_schema}.${state_abbrev}_${lookup_name};"',  ARRAY['gid','geoidfq', 'statefp','fromarmid', 'toarmid']);

INSERT INTO loader_lookuptables(process_order, lookup_name, table_name, load, level_county, level_state, single_geom_mode, insert_mode, pre_load_process, post_load_process,columns_exclude )
VALUES(9, 'addrfeat', 'addrfeat', false, true, false,true, 'a',
	'${psql} -c "CREATE TABLE ${data_schema}.${state_abbrev}_${lookup_name}(CONSTRAINT pk_${state_abbrev}_${table_name} PRIMARY KEY (gid)) INHERITS(tiger.${table_name});ALTER TABLE ${data_schema}.${state_abbrev}_${lookup_name} ALTER COLUMN statefp SET DEFAULT ''${state_fips}'';" ',
	'${psql} -c "ALTER TABLE ${data_schema}.${state_abbrev}_${lookup_name} ADD CONSTRAINT chk_statefp CHECK (statefp = ''${state_fips}'');"
	${psql} -c "vacuum analyze ${data_schema}.${state_abbrev}_${lookup_name};"',  ARRAY['gid','statefp','fromarmid', 'toarmid']);

CREATE OR REPLACE FUNCTION loader_generate_nation_script(os text)
  RETURNS SETOF text AS
$BODY$
WITH lu AS (SELECT lookup_name, table_name, pre_load_process,post_load_process, process_order, insert_mode, single_geom_mode, level_nation, level_county, level_state
    FROM  loader_lookuptables
				WHERE level_nation = true AND load = true)
SELECT
	loader_macro_replace(
		replace(
			loader_macro_replace(declare_sect
				, ARRAY['staging_fold', 'website_root', 'psql',  'data_schema', 'staging_schema'],
				ARRAY[variables.staging_fold, variables.website_root, platform.psql, variables.data_schema, variables.staging_schema]
			), '/', platform.path_sep) || '
'  ||
	-- Nation level files
	array_to_string( ARRAY(SELECT loader_macro_replace('cd ' || replace(variables.staging_fold,'/', platform.path_sep) || '
' || platform.wget || ' ' || variables.website_root  || '/'

-- hardcoding zcta5 path since doesn't follow convention
|| upper(CASE WHEN table_name = 'zcta510' THEN 'zcta5' ELSE table_name END)  || '/tl_' || variables.tiger_year || '_us_' || lower(table_name) || '.zip --mirror --reject=html
'
|| 'cd ' ||  replace(variables.staging_fold,'/', platform.path_sep) || '/' || replace(regexp_replace(variables.website_root, 'http[s]?://', ''),'ftp://','')  || '/'
-- note have to hard-code folder path for zcta because doesn't follow convention
|| upper(CASE WHEN table_name = 'zcta510' THEN 'zcta5' ELSE table_name END)  || '
' || replace(platform.unzip_command, '*.zip', 'tl_*' || table_name || '.zip ') || '
' || COALESCE(lu.pre_load_process || E'\n', '') || platform.loader || ' -D -' ||  lu.insert_mode || ' -s 4269 -g the_geom '
		|| CASE WHEN lu.single_geom_mode THEN ' -S ' ELSE ' ' END::text || ' -W "latin1" tl_' || variables.tiger_year
	|| '_us_' || lu.table_name || '.dbf tiger_staging.' || lu.table_name || ' | '::text || platform.psql
		|| COALESCE(E'\n' ||
			lu.post_load_process , '') , ARRAY['loader','table_name', 'lookup_name'], ARRAY[platform.loader, lu.table_name, lu.lookup_name ]
			)
				FROM lu
				ORDER BY process_order, lookup_name), E'\n') ::text
	, ARRAY['psql', 'data_schema','staging_schema', 'staging_fold', 'website_root'],
	ARRAY[platform.psql,  variables.data_schema, variables.staging_schema, variables.staging_fold, variables.website_root])
			AS shell_code
FROM tiger.loader_variables As variables
	 CROSS JOIN tiger.loader_platform As platform
WHERE platform.os = $1 -- generate script for selected platform
;
$BODY$
  LANGUAGE sql VOLATILE;

CREATE OR REPLACE FUNCTION loader_generate_script(param_states text[], os text)
  RETURNS SETOF text AS
$BODY$
SELECT
	loader_macro_replace(
		replace(
			loader_macro_replace(declare_sect
				, ARRAY['staging_fold', 'state_fold','website_root', 'psql', 'state_abbrev', 'data_schema', 'staging_schema', 'state_fips'],
				ARRAY[variables.staging_fold, s.state_fold, variables.website_root, platform.psql, s.state_abbrev, variables.data_schema, variables.staging_schema, s.state_fips::text]
			), '/', platform.path_sep) || '
' ||
	-- State level files - if an override website is specified we use that instead of variable one
	array_to_string( ARRAY(SELECT 'cd ' || replace(variables.staging_fold,'/', platform.path_sep) || '
' || platform.wget || ' ' || COALESCE(lu.website_root_override,variables.website_root || '/' || upper(lookup_name)  ) || '/tl_' || variables.tiger_year || '_' || s.state_fips || '_' || lower(table_name) || '.zip --mirror --reject=html
'
|| 'cd ' ||  replace(variables.staging_fold,'/', platform.path_sep) || '/' || replace(regexp_replace(COALESCE(lu.website_root_override, variables.website_root || '/' || upper(lookup_name) ), 'http[s]?://', ''),'ftp://','')    || '
' || replace(platform.unzip_command, '*.zip', 'tl_' || variables.tiger_year || '_' || s.state_fips || '*_' || table_name || '.zip ') || '
' ||loader_macro_replace(COALESCE(lu.pre_load_process || E'\n', '') || platform.loader || ' -D -' ||  lu.insert_mode || ' -s 4269 -g the_geom '
		|| CASE WHEN lu.single_geom_mode THEN ' -S ' ELSE ' ' END::text || ' -W "latin1" tl_' || variables.tiger_year || '_' || s.state_fips
	|| '_' || lu.table_name || '.dbf tiger_staging.' || lower(s.state_abbrev) || '_' || lu.table_name || ' | '::text || platform.psql
		|| COALESCE(E'\n' ||
			lu.post_load_process , '') , ARRAY['loader','table_name', 'lookup_name'], ARRAY[platform.loader, lu.table_name, lu.lookup_name ])
				FROM tiger.loader_lookuptables AS lu
				WHERE level_state = true AND load = true
				ORDER BY process_order, lookup_name), E'\n') ::text
	-- County Level files
	|| E'\n' ||
		array_to_string( ARRAY(SELECT 'cd ' || replace(variables.staging_fold,'/', platform.path_sep) || '
' ||
-- explode county files create wget call for each county file
array_to_string (ARRAY(SELECT platform.wget || ' --mirror  ' || COALESCE(lu.website_root_override, variables.website_root || '/' || upper(lookup_name)  ) || '/tl_' || variables.tiger_year || '_' || s.state_fips || c.countyfp || '_' || lower(table_name) || '.zip ' || E'\n'  AS county_out
FROM tiger.county As c
WHERE c.statefp = s.state_fips), ' ')
|| 'cd ' ||  replace(variables.staging_fold,'/', platform.path_sep) || '/' || replace(regexp_replace(COALESCE(lu.website_root_override,variables.website_root || '/' || upper(lookup_name)  || '/'), 'http[s]?://', ''),'ftp://','')  || '
' || replace(platform.unzip_command, '*.zip', 'tl_*_' || s.state_fips || '*_' || table_name || '*.zip ') || '
' || loader_macro_replace(COALESCE(lu.pre_load_process || E'\n', '') || COALESCE(county_process_command || E'\n','')
				|| COALESCE(E'\n' ||lu.post_load_process , '') , ARRAY['loader','table_name','lookup_name'], ARRAY[platform.loader  || ' -D ' || CASE WHEN lu.single_geom_mode THEN ' -S' ELSE ' ' END::text, lu.table_name, lu.lookup_name ])
				FROM tiger.loader_lookuptables AS lu
				WHERE level_county = true AND load = true
				ORDER BY process_order, lookup_name), E'\n') ::text
	, ARRAY['psql', 'data_schema','staging_schema', 'staging_fold', 'state_fold', 'website_root', 'state_abbrev','state_fips'],
	ARRAY[platform.psql,  variables.data_schema, variables.staging_schema, variables.staging_fold, s.state_fold,variables.website_root, s.state_abbrev, s.state_fips::text])
			AS shell_code
FROM loader_variables As variables
		CROSS JOIN (SELECT name As state, abbrev As state_abbrev, lpad(st_code::text,2,'0') As state_fips,
			 lpad(st_code::text,2,'0') || '_'
	|| replace(name, ' ', '_') As state_fold
FROM tiger.state_lookup) As s CROSS JOIN tiger.loader_platform As platform
WHERE $1 @> ARRAY[state_abbrev::text]      -- If state is contained in list of states input generate script for it
AND platform.os = $2  -- generate script for selected platform
;
$BODY$
  LANGUAGE sql VOLATILE;

CREATE OR REPLACE FUNCTION loader_load_staged_data(param_staging_table text, param_target_table text, param_columns_exclude text[]) RETURNS integer
AS
$$
DECLARE
	var_sql text;
	var_staging_schema text; var_data_schema text;
	var_temp text;
	var_num_records bigint;
BEGIN
-- Add all the fields except geoid and gid
-- Assume all the columns are in same order as target
	SELECT staging_schema, data_schema INTO var_staging_schema, var_data_schema FROM loader_variables;
	var_sql := 'INSERT INTO ' || var_data_schema || '.' || quote_ident(param_target_table) || '(' ||
			array_to_string(ARRAY(SELECT quote_ident(column_name::text)
				FROM information_schema.columns
				 WHERE table_name = param_target_table
					AND table_schema = var_data_schema
					AND column_name <> ALL(param_columns_exclude)
                    ORDER BY column_name ), ',') || ') SELECT '
					|| array_to_string(ARRAY(SELECT quote_ident(column_name::text)
				FROM information_schema.columns
				 WHERE table_name = param_staging_table
					AND table_schema = var_staging_schema
					AND column_name <> ALL( param_columns_exclude)
                    ORDER BY column_name ), ',') ||' FROM '
					|| var_staging_schema || '.' || param_staging_table || ';';
	RAISE NOTICE '%', var_sql;
	EXECUTE (var_sql);
	GET DIAGNOSTICS var_num_records = ROW_COUNT;
	SELECT DropGeometryTable(var_staging_schema,param_staging_table) INTO var_temp;
	RETURN var_num_records;
END;
$$
LANGUAGE 'plpgsql' VOLATILE;

CREATE OR REPLACE FUNCTION loader_load_staged_data(param_staging_table text, param_target_table text)
RETURNS integer AS
$$
-- exclude this set list of columns if no exclusion list is specified

   SELECT  tiger.loader_load_staged_data($1, $2,(SELECT COALESCE(columns_exclude,ARRAY['gid', 'geoid',  'geoidfq20', 'cpi','suffix1ce', 'statefp00', 'statefp10', 'countyfp00','countyfp10'
   ,'tractce00','tractce10', 'blkgrpce00', 'blkgrpce10', 'blockce00', 'blockce10'
      , 'cousubfp00', 'submcdfp00', 'conctyfp00', 'placefp00', 'aiannhfp00', 'aiannhce00'
      , 'comptyp00', 'trsubfp00', 'trsubce00', 'anrcfp00', 'elsdlea00', 'scsdlea00',
       'unsdlea00', 'uace00', 'cd108fp', 'sldust00', 'sldlst00', 'vtdst00', 'zcta5ce00',
       'tazce00', 'ugace00', 'puma5ce00','vtdst10','tazce10','uace10','puma5ce10','tazce', 'uace', 'vtdst', 'zcta5ce', 'zcta5ce10', 'puma5ce', 'ugace10','pumace10', 'estatefp', 'ugace', 'blockce', 'cnectafp', 'geoidfq', 'nctadvfp', 'nectafp','pcinecta' ]) FROM loader_lookuptables WHERE $2 LIKE '%' || lookup_name))
$$
language 'sql' VOLATILE;

CREATE OR REPLACE FUNCTION loader_generate_census_script(param_states text[], os text)
  RETURNS SETOF text AS
$$
SELECT create_census_base_tables();
SELECT
	loader_macro_replace(
		replace(
			loader_macro_replace(declare_sect
				, ARRAY['staging_fold', 'state_fold','website_root', 'psql', 'state_abbrev', 'data_schema', 'staging_schema', 'state_fips'],
				ARRAY[variables.staging_fold, s.state_fold, variables.website_root, platform.psql, s.state_abbrev, variables.data_schema, variables.staging_schema, s.state_fips::text]
			), '/', platform.path_sep) || '
' ||
	-- State level files - if an override website is specified we use that instead of variable one
	array_to_string( ARRAY(SELECT 'cd ' || replace(variables.staging_fold,'/', platform.path_sep) || '
' || platform.wget || ' ' || COALESCE(lu.website_root_override,variables.website_root || '/' || upper(lookup_name)  ) || '/tl_' || variables.tiger_year || '_' || s.state_fips || '_' || lower(table_name) || '.zip --mirror --reject=html
'
|| 'cd ' ||  replace(variables.staging_fold,'/', platform.path_sep) || '/' || replace(regexp_replace(COALESCE(lu.website_root_override,variables.website_root || '/' || upper(lookup_name) ), 'http[s]+://', ''),'ftp://','')    || '
' || replace(platform.unzip_command, '*.zip', 'tl_' || variables.tiger_year || '_' || s.state_fips || '*_' || table_name || '.zip ') || '
' ||loader_macro_replace(COALESCE(lu.pre_load_process || E'\n', '') || platform.loader || ' -D -' ||  lu.insert_mode || ' -s 4269 -g the_geom '
		|| CASE WHEN lu.single_geom_mode THEN ' -S ' ELSE ' ' END::text || ' -W "latin1" tl_' || variables.tiger_year || '_' || s.state_fips
	|| '_' || lu.table_name || '.dbf tiger_staging.' || lower(s.state_abbrev) || '_' || lu.table_name || ' | '::text || platform.psql
		|| COALESCE(E'\n' ||
			lu.post_load_process , '') , ARRAY['loader','table_name', 'lookup_name'], ARRAY[platform.loader, lu.table_name, lu.lookup_name ])
				FROM loader_lookuptables AS lu
				WHERE level_state = true AND lu.lookup_name IN('bg','tract', 'tabblock')
				ORDER BY process_order, lookup_name), E'\n') ::text
	-- County Level files
	|| E'\n' ||
		array_to_string( ARRAY(SELECT 'cd ' || replace(variables.staging_fold,'/', platform.path_sep) || '
' ||
-- explode county files create wget call for each county file
array_to_string (ARRAY(SELECT platform.wget || ' --mirror  ' || COALESCE(lu.website_root_override,variables.website_root || '/' || upper(lookup_name)  ) || '/tl_' || variables.tiger_year || '_' || s.state_fips || c.countyfp || '_' || lower(table_name) || '.zip ' || E'\n'  AS county_out
FROM tiger.county As c
WHERE c.statefp = s.state_fips), ' ')
|| 'cd ' ||  replace(variables.staging_fold,'/', platform.path_sep) || '/' || replace(regexp_replace(COALESCE(lu.website_root_override,variables.website_root || '/' || upper(lookup_name)  || '/'), 'http[s]+://', ''),'ftp://','')  || '
' || replace(platform.unzip_command, '*.zip', 'tl_*_' || s.state_fips || '*_' || table_name || '*.zip ') || '
' || loader_macro_replace(COALESCE(lu.pre_load_process || E'\n', '') || COALESCE(county_process_command || E'\n','')
				|| COALESCE(E'\n' ||lu.post_load_process , '') , ARRAY['loader','table_name','lookup_name'], ARRAY[platform.loader  || ' -D ' || CASE WHEN lu.single_geom_mode THEN ' -S' ELSE ' ' END::text, lu.table_name, lu.lookup_name ])
				FROM loader_lookuptables AS lu
				WHERE level_county = true AND lu.lookup_name IN('bg','tract', 'tabblock')
				ORDER BY process_order, lookup_name), E'\n') ::text
	, ARRAY['psql', 'data_schema','staging_schema', 'staging_fold', 'state_fold', 'website_root', 'state_abbrev','state_fips'],
	ARRAY[platform.psql,  variables.data_schema, variables.staging_schema, variables.staging_fold, s.state_fold,variables.website_root, s.state_abbrev, s.state_fips::text])
			AS shell_code
FROM loader_variables As variables
		CROSS JOIN (SELECT name As state, abbrev As state_abbrev, lpad(st_code::text,2,'0') As state_fips,
			 lpad(st_code::text,2,'0') || '_'
	|| replace(name, ' ', '_') As state_fold
FROM state_lookup) As s CROSS JOIN loader_platform As platform
WHERE $1 @> ARRAY[state_abbrev::text]      -- If state is contained in list of states input generate script for it
AND platform.os = $2  -- generate script for selected platform
;
$$
  LANGUAGE sql VOLATILE;

SELECT create_census_base_tables();

CREATE OR REPLACE FUNCTION utmzone(geometry) RETURNS integer AS
$BODY$
DECLARE
    geomgeog geometry;
    zone int;
    pref int;
BEGIN
    geomgeog:=ST_Transform($1,4326);
    IF (ST_Y(geomgeog))>0 THEN
        pref:=32600;
    ELSE
        pref:=32700;
    END IF;
    zone:=floor((ST_X(geomgeog)+180)/6)+1;
    RETURN zone+pref;
END;
$BODY$ LANGUAGE 'plpgsql' immutable;
-- Returns the value passed, or an empty string if null.
-- This is used to concatinate values that may be null.
CREATE OR REPLACE FUNCTION cull_null(VARCHAR) RETURNS VARCHAR
AS $_$
    SELECT coalesce($1,'');
$_$ LANGUAGE sql IMMUTABLE;
-- This function take two arguments.  The first is the "given string" and
-- must not be null.  The second argument is the "compare string" and may
-- or may not be null.  If the second string is null, the value returned is
-- 3, otherwise it is the levenshtein difference between the two.
-- Change 2010-10-18 Regina Obe - name verbose to var_verbose since get compile error in PostgreSQL 9.0
CREATE OR REPLACE FUNCTION nullable_levenshtein(VARCHAR, VARCHAR) RETURNS INTEGER
AS $_$
DECLARE
  given_string VARCHAR;
  result INTEGER := 3;
  var_verbose BOOLEAN := FALSE; /**change from verbose to param_verbose since its a keyword and get compile error in 9.0 **/
BEGIN
  IF $1 IS NULL THEN
    IF var_verbose THEN
      RAISE NOTICE 'nullable_levenshtein - given string is NULL!';
    END IF;
    RETURN NULL;
  ELSE
    given_string := $1;
  END IF;

  IF $2 IS NOT NULL AND $2 != '' THEN
    result := levenshtein_ignore_case(given_string, $2);
  END IF;

  RETURN result;
END
$_$ LANGUAGE plpgsql IMMUTABLE COST 10;
-- This function determines the levenshtein distance irespective of case.
CREATE OR REPLACE FUNCTION levenshtein_ignore_case(VARCHAR, VARCHAR) RETURNS INTEGER
AS $_$
  SELECT levenshtein(COALESCE(upper($1),''), COALESCE(upper($2),''));
$_$ LANGUAGE sql IMMUTABLE;
-- Runs the soundex function on the last word in the string provided.
-- Words are allowed to be separated by space, comma, period, new-line
-- tab or form feed.
CREATE OR REPLACE FUNCTION end_soundex(VARCHAR) RETURNS VARCHAR
AS $_$
DECLARE
  tempString VARCHAR;
BEGIN
  tempString := substring($1, E'[ ,.\n\t\f]([a-zA-Z0-9]*)$');
  IF tempString IS NOT NULL THEN
    tempString := soundex(tempString);
  ELSE
    tempString := soundex($1);
  END IF;
  return tempString;
END;
$_$ LANGUAGE plpgsql IMMUTABLE;
-- Determine the number of words in a string.  Words are allowed to
-- be separated only by spaces, but multiple spaces between
-- words are allowed.
CREATE OR REPLACE FUNCTION count_words(VARCHAR) RETURNS INTEGER
AS $_$
DECLARE
  tempString VARCHAR;
  tempInt INTEGER;
  count INTEGER := 1;
  lastSpace BOOLEAN := FALSE;
BEGIN
  IF $1 IS NULL THEN
    return -1;
  END IF;
  tempInt := length($1);
  IF tempInt = 0 THEN
    return 0;
  END IF;
  FOR i IN 1..tempInt LOOP
    tempString := substring($1 from i for 1);
    IF tempString = ' ' THEN
      IF NOT lastSpace THEN
        count := count + 1;
      END IF;
      lastSpace := TRUE;
    ELSE
      lastSpace := FALSE;
    END IF;
  END LOOP;
  return count;
END;
$_$ LANGUAGE plpgsql IMMUTABLE;
-- state_extract(addressStringLessZipCode)
-- Extracts the state from end of the given string.
--
-- This function uses the state_lookup table to determine which state
-- the input string is indicating.  First, an exact match is pursued,
-- and in the event of failure, a word-by-word fuzzy match is attempted.
--
-- The result is the state as given in the input string, and the approved
-- state abbreviation, separated by a colon.
CREATE OR REPLACE FUNCTION state_extract(rawInput VARCHAR) RETURNS VARCHAR
AS $_$
DECLARE
  tempInt INTEGER;
  tempString VARCHAR;
  state VARCHAR;
  stateAbbrev VARCHAR;
  result VARCHAR;
  rec RECORD;
  test BOOLEAN;
  ws VARCHAR;
  var_verbose boolean := false;
BEGIN
  ws := E'[ ,.\t\n\f\r]';

  -- If there is a trailing space or , get rid of it
  -- this is to handle case where people use , instead of space to separate state and zip
  -- such as '2450 N COLORADO ST, PHILADELPHIA, PA, 19132' instead of '2450 N COLORADO ST, PHILADELPHIA, PA 19132'

  --tempString := regexp_replace(rawInput, E'(.*)' || ws || '+', E'\\1');
  tempString := btrim(rawInput, ', ');
  -- Separate out the last word of the state, and use it to compare to
  -- the state lookup table to determine the entire name, as well as the
  -- abbreviation associated with it.  The zip code may or may not have
  -- been found.
  tempString := substring(tempString from ws || E'+([^ ,.\t\n\f\r0-9]*?)$');
  IF var_verbose THEN RAISE NOTICE 'state_extract rawInput: % tempString: %', rawInput, tempString; END IF;
  SELECT INTO tempInt count(*) FROM (select distinct abbrev from state_lookup
      WHERE upper(abbrev) = upper(tempString)) as blah;
  IF tempInt = 1 THEN
    state := tempString;
    SELECT INTO stateAbbrev abbrev FROM (select distinct abbrev from
        state_lookup WHERE upper(abbrev) = upper(tempString)) as blah;
  ELSE
    SELECT INTO tempInt count(*) FROM state_lookup WHERE upper(name)
        like upper('%' || tempString);
    IF tempInt >= 1 THEN
      FOR rec IN SELECT name from state_lookup WHERE upper(name)
          like upper('%' || tempString) LOOP
        SELECT INTO test texticregexeq(rawInput, name) FROM state_lookup
            WHERE rec.name = name;
        IF test THEN
          SELECT INTO stateAbbrev abbrev FROM state_lookup
              WHERE rec.name = name;
          state := substring(rawInput, '(?i)' || rec.name);
          EXIT;
        END IF;
      END LOOP;
    ELSE
      -- No direct match for state, so perform fuzzy match.
      SELECT INTO tempInt count(*) FROM state_lookup
          WHERE soundex(tempString) = end_soundex(name);
      IF tempInt >= 1 THEN
        FOR rec IN SELECT name, abbrev FROM state_lookup
            WHERE soundex(tempString) = end_soundex(name) LOOP
          tempInt := count_words(rec.name);
          tempString := get_last_words(rawInput, tempInt);
          test := TRUE;
          FOR i IN 1..tempInt LOOP
            IF soundex(split_part(tempString, ' ', i)) !=
               soundex(split_part(rec.name, ' ', i)) THEN
              test := FALSE;
            END IF;
          END LOOP;
          IF test THEN
            state := tempString;
            stateAbbrev := rec.abbrev;
            EXIT;
          END IF;
        END LOOP;
      END IF;
    END IF;
  END IF;

  IF state IS NOT NULL AND stateAbbrev IS NOT NULL THEN
    result := state || ':' || stateAbbrev;
  END IF;

  RETURN result;
END;
$_$ LANGUAGE plpgsql STABLE;
-- Returns a string consisting of the last N words.  Words are allowed
-- to be separated only by spaces, but multiple spaces between
-- words are allowed.  Words must be alphanumberic.
-- If more words are requested than exist, the full input string is
-- returned.
CREATE OR REPLACE FUNCTION get_last_words(
    inputString VARCHAR,
    count INTEGER
) RETURNS VARCHAR
AS $_$
DECLARE
  tempString VARCHAR;
  result VARCHAR := '';
BEGIN
  FOR i IN 1..count LOOP
    tempString := substring(inputString from '((?: )+[a-zA-Z0-9_]*)' || result || '$');

    IF tempString IS NULL THEN
      RETURN inputString;
    END IF;

    result := tempString || result;
  END LOOP;

  result := trim(both from result);

  RETURN result;
END;
$_$ LANGUAGE plpgsql IMMUTABLE COST 10;
-- location_extract_countysub_exact(string, stateAbbrev)
-- This function checks the place_lookup table to find a potential match to
-- the location described at the end of the given string.  If an exact match
-- fails, a fuzzy match is performed.  The location as found in the given
-- string is returned.
CREATE OR REPLACE FUNCTION location_extract_countysub_exact(
    fullStreet VARCHAR,
    stateAbbrev VARCHAR
) RETURNS VARCHAR
AS $_$
DECLARE
  ws VARCHAR;
  location VARCHAR;
  tempInt INTEGER;
  lstate VARCHAR;
  rec RECORD;
BEGIN
  ws := E'[ ,.\n\f\t]';

  -- No hope of determining the location from place. Try countysub.
  IF stateAbbrev IS NOT NULL THEN
    lstate := statefp FROM state WHERE stusps = stateAbbrev;
    SELECT INTO tempInt count(*) FROM cousub
        WHERE cousub.statefp = lstate
        AND texticregexeq(fullStreet, '(?i)' || name || '$');
  ELSE
    SELECT INTO tempInt count(*) FROM cousub
        WHERE texticregexeq(fullStreet, '(?i)' || name || '$');
  END IF;

  IF tempInt > 0 THEN
    IF stateAbbrev IS NOT NULL THEN
      FOR rec IN SELECT substring(fullStreet, '(?i)('
          || name || ')$') AS value, name FROM cousub
          WHERE cousub.statefp = lstate
          AND texticregexeq(fullStreet, '(?i)' || ws || name ||
          '$') ORDER BY length(name) DESC LOOP
        -- Only the first result is needed.
        location := rec.value;
        EXIT;
      END LOOP;
    ELSE
      FOR rec IN SELECT substring(fullStreet, '(?i)('
          || name || ')$') AS value, name FROM cousub
          WHERE texticregexeq(fullStreet, '(?i)' || ws || name ||
          '$') ORDER BY length(name) DESC LOOP
        -- again, only the first is needed.
        location := rec.value;
        EXIT;
      END LOOP;
    END IF;
  END IF;

  RETURN location;
END;
$_$ LANGUAGE plpgsql STABLE COST 10;
-- location_extract_countysub_fuzzy(string, stateAbbrev)
-- This function checks the place_lookup table to find a potential match to
-- the location described at the end of the given string.  If an exact match
-- fails, a fuzzy match is performed.  The location as found in the given
-- string is returned.
CREATE OR REPLACE FUNCTION location_extract_countysub_fuzzy(
    fullStreet VARCHAR,
    stateAbbrev VARCHAR
) RETURNS VARCHAR
AS $_$
DECLARE
  ws VARCHAR;
  tempString VARCHAR;
  location VARCHAR;
  tempInt INTEGER;
  word_count INTEGER;
  rec RECORD;
  test BOOLEAN;
  lstate VARCHAR;
BEGIN
  ws := E'[ ,.\n\f\t]';

  -- Fuzzy matching.
  tempString := substring(fullStreet, '(?i)' || ws ||
      '([a-zA-Z0-9]+)$');
  IF tempString IS NULL THEN
    tempString := fullStreet;
  END IF;

  IF stateAbbrev IS NOT NULL THEN
    lstate := statefp FROM state WHERE stusps = stateAbbrev;
    SELECT INTO tempInt count(*) FROM cousub
        WHERE cousub.statefp = lstate
        AND soundex(tempString) = end_soundex(name);
  ELSE
    SELECT INTO tempInt count(*) FROM cousub
        WHERE soundex(tempString) = end_soundex(name);
  END IF;

  IF tempInt > 0 THEN
    tempInt := 50;
    -- Some potentials were found.  Begin a word-by-word soundex on each.
    IF stateAbbrev IS NOT NULL THEN
      FOR rec IN SELECT name FROM cousub
          WHERE cousub.statefp = lstate
          AND soundex(tempString) = end_soundex(name) LOOP
        word_count := count_words(rec.name);
        test := TRUE;
        tempString := get_last_words(fullStreet, word_count);
        FOR i IN 1..word_count LOOP
          IF soundex(split_part(tempString, ' ', i)) !=
            soundex(split_part(rec.name, ' ', i)) THEN
            test := FALSE;
          END IF;
        END LOOP;
        IF test THEN
          -- The soundex matched, determine if the distance is better.
          IF levenshtein_ignore_case(rec.name, tempString) < tempInt THEN
                location := tempString;
            tempInt := levenshtein_ignore_case(rec.name, tempString);
          END IF;
        END IF;
      END LOOP;
    ELSE
      FOR rec IN SELECT name FROM cousub
          WHERE soundex(tempString) = end_soundex(name) LOOP
        word_count := count_words(rec.name);
        test := TRUE;
        tempString := get_last_words(fullStreet, word_count);
        FOR i IN 1..word_count LOOP
          IF soundex(split_part(tempString, ' ', i)) !=
            soundex(split_part(rec.name, ' ', i)) THEN
            test := FALSE;
          END IF;
        END LOOP;
        IF test THEN
          -- The soundex matched, determine if the distance is better.
          IF levenshtein_ignore_case(rec.name, tempString) < tempInt THEN
                location := tempString;
            tempInt := levenshtein_ignore_case(rec.name, tempString);
          END IF;
        END IF;
      END LOOP;
    END IF;
  END IF; -- If no fuzzys were found, leave location null.

  RETURN location;
END;
$_$ LANGUAGE plpgsql;
-- location_extract_place_exact(string, stateAbbrev)
-- This function checks the place_lookup table to find a potential match to
-- the location described at the end of the given string.  If an exact match
-- fails, a fuzzy match is performed.  The location as found in the given
-- string is returned.
CREATE OR REPLACE FUNCTION location_extract_place_exact(
    fullStreet VARCHAR,
    stateAbbrev VARCHAR
) RETURNS VARCHAR
AS $_$
DECLARE
  ws VARCHAR;
  location VARCHAR;
  tempInt INTEGER;
  lstate VARCHAR;
  rec RECORD;
BEGIN
  ws := E'[ ,.\n\f\t]';

  -- Try for an exact match against places
  IF stateAbbrev IS NOT NULL THEN
    lstate := statefp FROM state WHERE stusps = stateAbbrev;
    SELECT INTO tempInt count(*) FROM place
        WHERE place.statefp = lstate AND fullStreet ILIKE '%' || name || '%'
        AND texticregexeq(fullStreet, '(?i)' || name || '$');
  ELSE
    SELECT INTO tempInt count(*) FROM place
        WHERE fullStreet ILIKE '%' || name || '%' AND
        	texticregexeq(fullStreet, '(?i)' || name || '$');
  END IF;

  IF tempInt > 0 THEN
    -- Some matches were found.  Look for the last one in the string.
    IF stateAbbrev IS NOT NULL THEN
      FOR rec IN SELECT substring(fullStreet, '(?i)('
          || name || ')$') AS value, name FROM place
          WHERE place.statefp = lstate AND fullStreet ILIKE '%' || name || '%'
          AND texticregexeq(fullStreet, '(?i)'
          || name || '$') ORDER BY length(name) DESC LOOP
        -- Since the regex is end of string, only the longest (first) result
        -- is useful.
        location := rec.value;
        EXIT;
      END LOOP;
    ELSE
      FOR rec IN SELECT substring(fullStreet, '(?i)('
          || name || ')$') AS value, name FROM place
          WHERE fullStreet ILIKE '%' || name || '%' AND texticregexeq(fullStreet, '(?i)'
          || name || '$') ORDER BY length(name) DESC LOOP
        -- Since the regex is end of string, only the longest (first) result
        -- is useful.
        location := rec.value;
        EXIT;
      END LOOP;
    END IF;
  END IF;

  RETURN location;
END;
$_$ LANGUAGE plpgsql STABLE COST 100;
-- location_extract_place_fuzzy(string, stateAbbrev)
-- This function checks the place_lookup table to find a potential match to
-- the location described at the end of the given string.  If an exact match
-- fails, a fuzzy match is performed.  The location as found in the given
-- string is returned.
CREATE OR REPLACE FUNCTION location_extract_place_fuzzy(
    fullStreet VARCHAR,
    stateAbbrev VARCHAR
) RETURNS VARCHAR
AS $_$
DECLARE
  ws VARCHAR;
  tempString VARCHAR;
  location VARCHAR;
  tempInt INTEGER;
  word_count INTEGER;
  rec RECORD;
  test BOOLEAN;
  lstate VARCHAR;
BEGIN
  ws := E'[ ,.\n\f\t]';

  tempString := substring(fullStreet, '(?i)' || ws
      || '([a-zA-Z0-9]+)$');
  IF tempString IS NULL THEN
      tempString := fullStreet;
  END IF;

  IF stateAbbrev IS NOT NULL THEN
    lstate := statefp FROM state WHERE stusps = stateAbbrev;
    SELECT into tempInt count(*) FROM place
        WHERE place.statefp = lstate
        AND soundex(tempString) = end_soundex(name);
  ELSE
    SELECT into tempInt count(*) FROM place
        WHERE soundex(tempString) = end_soundex(name);
  END IF;

  IF tempInt > 0 THEN
    -- Some potentials were found.  Begin a word-by-word soundex on each.
    tempInt := 50;
    IF stateAbbrev IS NOT NULL THEN
      FOR rec IN SELECT name FROM place
          WHERE place.statefp = lstate
          AND soundex(tempString) = end_soundex(name) LOOP
        word_count := count_words(rec.name);
        test := TRUE;
        tempString := get_last_words(fullStreet, word_count);
        FOR i IN 1..word_count LOOP
          IF soundex(split_part(tempString, ' ', i)) !=
            soundex(split_part(rec.name, ' ', i)) THEN
            test := FALSE;
          END IF;
        END LOOP;
          IF test THEN
            -- The soundex matched, determine if the distance is better.
            IF levenshtein_ignore_case(rec.name, tempString) < tempInt THEN
              location := tempString;
              tempInt := levenshtein_ignore_case(rec.name, tempString);
            END IF;
          END IF;
      END LOOP;
    ELSE
      FOR rec IN SELECT name FROM place
          WHERE soundex(tempString) = end_soundex(name) LOOP
        word_count := count_words(rec.name);
        test := TRUE;
        tempString := get_last_words(fullStreet, word_count);
        FOR i IN 1..word_count LOOP
          IF soundex(split_part(tempString, ' ', i)) !=
            soundex(split_part(rec.name, ' ', i)) THEN
            test := FALSE;
          END IF;
        END LOOP;
          IF test THEN
            -- The soundex matched, determine if the distance is better.
            IF levenshtein_ignore_case(rec.name, tempString) < tempInt THEN
              location := tempString;
            tempInt := levenshtein_ignore_case(rec.name, tempString);
          END IF;
        END IF;
      END LOOP;
    END IF;
  END IF;

  RETURN location;
END;
$_$ LANGUAGE plpgsql STABLE;
-- location_extract(streetAddressString, stateAbbreviation)
-- This function extracts a location name from the end of the given string.
-- The first attempt is to find an exact match against the place_lookup
-- table.  If this fails, a word-by-word soundex match is tried against the
-- same table.  If multiple candidates are found, the one with the smallest
-- levenshtein distance from the given string is assumed the correct one.
-- If no match is found against the place_lookup table, the same tests are
-- run against the countysub_lookup table.
--
-- The section of the given string corresponding to the location found is
-- returned, rather than the string found from the tables.  All the searching
-- is done largely to determine the length (words) of the location, to allow
-- the intended street name to be correctly identified.
CREATE OR REPLACE FUNCTION location_extract(fullStreet VARCHAR, stateAbbrev VARCHAR) RETURNS VARCHAR
AS $_$
DECLARE
  ws VARCHAR;
  location VARCHAR;
  lstate VARCHAR;
  stmt VARCHAR;
  street_array text[];
  word_count INTEGER;
  rec RECORD;
  best INTEGER := 0;
  tempString VARCHAR;
BEGIN
  IF fullStreet IS NULL THEN
    RETURN NULL;
  END IF;

  ws := E'[ ,.\n\f\t]';

  IF stateAbbrev IS NOT NULL THEN
    lstate := statefp FROM state_lookup WHERE abbrev = stateAbbrev;
  END IF;
  lstate := COALESCE(lstate,'');

  street_array := regexp_split_to_array(fullStreet,ws);
  word_count := array_upper(street_array,1);

  tempString := '';
  FOR i IN 1..word_count LOOP
    CONTINUE WHEN street_array[word_count-i+1] IS NULL OR street_array[word_count-i+1] = '';

    tempString := COALESCE(street_array[word_count-i+1],'') || tempString;

    stmt := ' SELECT'
         || '   1,'
         || '   name,'
         || '   levenshtein_ignore_case(' || quote_literal(tempString) || ',name) as rating,'
         || '   length(name) as len'
         || ' FROM place'
         || ' WHERE ' || CASE WHEN stateAbbrev IS NOT NULL THEN 'statefp = ' || quote_literal(lstate) || ' AND ' ELSE '' END
         || '   soundex(' || quote_literal(tempString) || ') = soundex(name)'
         || '   AND levenshtein_ignore_case(' || quote_literal(tempString) || ',name) <= 2 '
         || ' UNION ALL SELECT'
         || '   2,'
         || '   name,'
         || '   levenshtein_ignore_case(' || quote_literal(tempString) || ',name) as rating,'
         || '   length(name) as len'
         || ' FROM cousub'
         || ' WHERE ' || CASE WHEN stateAbbrev IS NOT NULL THEN 'statefp = ' || quote_literal(lstate) || ' AND ' ELSE '' END
         || '   soundex(' || quote_literal(tempString) || ') = soundex(name)'
         || '   AND levenshtein_ignore_case(' || quote_literal(tempString) || ',name) <= 2 '
         || ' ORDER BY '
         || '   3 ASC, 1 ASC, 4 DESC'
         || ' LIMIT 1;'
         ;

    EXECUTE stmt INTO rec;

    IF rec.rating >= best THEN
      location := tempString;
      best := rec.rating;
    END IF;

    tempString := ' ' || tempString;
  END LOOP;

  location := replace(location,' ',ws || '+');
  location := substring(fullStreet,'(?i)' || location || '$');

  RETURN location;
END;
$_$ LANGUAGE plpgsql STABLE COST 100;
-- normalize_address(addressString)
-- This takes an address string and parses it into address (internal/street)
-- street name, type, direction prefix and suffix, location, state and
-- zip code, depending on what can be found in the string.
--
-- The US postal address standard is used:
-- <Street Number> <Direction Prefix> <Street Name> <Street Type>
-- <Direction Suffix> <Internal Address> <Location> <State> <Zip Code>
--
-- State is assumed to be included in the string, and MUST be matchable to
-- something in the state_lookup table.  Fuzzy matching is used if no direct
-- match is found.
--
-- Two formats of zip code are acceptable: five digit, and five + 4.
--
-- The internal addressing indicators are looked up from the
-- secondary_unit_lookup table.  A following identifier is accepted
-- but it must start with a digit.
--
-- The location is parsed from the string using other indicators, such
-- as street type, direction suffix or internal address, if available.
-- If these are not, the location is extracted using comparisons against
-- the places_lookup table, then the countysub_lookup table to determine
-- what, in the original string, is intended to be the location.  In both
-- cases, an exact match is first pursued, then a word-by-word fuzzy match.
-- The result is not the name of the location from the tables, but the
-- section of the given string that corresponds to the name from the tables.
--
-- Zip codes and street names are not validated.
--
-- Direction indicators are extracted by comparison with the direction_lookup
-- table.
--
-- Street addresses are assumed to be a single word, starting with a number.
-- Address is manditory; if no address is given, and the street is numbered,
-- the resulting address will be the street name, and the street name
-- will be an empty string.
--
-- In some cases, the street type is part of the street name.
-- eg State Hwy 22a.  As long as the word following the type starts with a
-- number (this is usually the case) this will be caught.  Some street names
-- include a type name, and have a street type that differs.  This will be
-- handled properly, so long as both are given.  If the street type is
-- omitted, the street names included type will be parsed as the street type.
--
-- The output is currently a colon separated list of values:
-- InternalAddress:StreetAddress:DirectionPrefix:StreetName:StreetType:
-- DirectionSuffix:Location:State:ZipCode
-- This returns each element as entered.  It's mainly meant for debugging.
-- There is also another option that returns:
-- StreetAddress:DirectionPrefixAbbreviation:StreetName:StreetTypeAbbreviation:
-- DirectionSuffixAbbreviation:Location:StateAbbreviation:ZipCode
-- This is more standardized and better for use with a geocoder.
CREATE OR REPLACE FUNCTION normalize_address(in_rawinput character varying)
  RETURNS norm_addy AS
$$
DECLARE
  debug_flag boolean := get_geocode_setting('debug_normalize_address')::boolean;
  use_pagc boolean := COALESCE(get_geocode_setting('use_pagc_address_parser')::boolean, false);
  result norm_addy;
  addressString VARCHAR;
  zipString VARCHAR;
  preDir VARCHAR;
  postDir VARCHAR;
  fullStreet VARCHAR;
  reducedStreet VARCHAR;
  streetType VARCHAR;
  state VARCHAR;
  tempString VARCHAR;
  tempInt INTEGER;
  rec RECORD;
  ws VARCHAR;
  rawInput VARCHAR;
  -- is this a highway
  -- (we treat these differently since the road name often comes after the streetType)
  isHighway boolean := false;
BEGIN
  result.parsed := FALSE;
  IF use_pagc THEN
  	result := pagc_normalize_address(in_rawinput);
  	RETURN result;
  END IF;

  rawInput := trim(in_rawInput);

  IF rawInput IS NULL THEN
    RETURN result;
  END IF;

  ws := E'[ ,.\t\n\f\r]';

  IF debug_flag THEN
    raise notice '% input: %', clock_timestamp(), rawInput;
  END IF;

  -- Assume that the address begins with a digit, and extract it from
  -- the input string.
  addressString := substring(rawInput from E'^([0-9].*?)[ ,/.]');

  -- try to pull full street number including non-digits like 1R
  result.address_alphanumeric := substring(rawInput from E'^([0-9a-zA-Z].*?)[ ,/.]');

  IF debug_flag THEN
    raise notice '% addressString: %', clock_timestamp(), addressString;
  END IF;

  -- There are two formats for zip code, the normal 5 digit , and
  -- the nine digit zip-4.  It may also not exist.

  zipString := substring(rawInput from ws || E'([0-9]{5})$');
  IF zipString IS NULL THEN
    -- Check if the zip is just a partial or a one with -s
    -- or one that just has more than 5 digits
    zipString := COALESCE(substring(rawInput from ws || '([0-9]{5})-[0-9]{0,4}$'),
                substring(rawInput from ws || '([0-9]{2,5})$'),
                substring(rawInput from ws || '([0-9]{6,14})$'));

    result.zip4 := COALESCE(substring(rawInput from ws || '[0-9]{5}-([0-9]{0,4})$'),substring(rawInput from ws || '[0-9]{5}([0-9]{0,4})$'));

    IF debug_flag THEN
        raise notice '% zip4: %', clock_timestamp(), result.zip4;
    END IF;
     -- Check if all we got was a zipcode, of either form
    IF zipString IS NULL THEN
      zipString := substring(rawInput from '^([0-9]{5})$');
      IF zipString IS NULL THEN
        zipString := substring(rawInput from '^([0-9]{5})-[0-9]{4}$');
      END IF;
      -- If it was only a zipcode, then just return it.
      IF zipString IS NOT NULL THEN
        result.zip := zipString;
        result.parsed := TRUE;
        RETURN result;
      END IF;
    END IF;
  END IF;

  IF debug_flag THEN
    raise notice '% zipString: %', clock_timestamp(), zipString;
  END IF;

  IF zipString IS NOT NULL THEN
    fullStreet := substring(rawInput from '(.*)'
        || ws || '+' || cull_null(zipString) || '[- ]?([0-9]{4})?$');
    /** strip off any trailing  spaces or ,**/
    fullStreet :=  btrim(fullStreet, ' ,');

  ELSE
    fullStreet := rawInput;
  END IF;

  IF debug_flag THEN
    raise notice '% fullStreet: %', clock_timestamp(), fullStreet;
  END IF;

  -- FIXME: state_extract should probably be returning a record so we can
  -- avoid having to parse the result from it.
  tempString := state_extract(fullStreet);
  IF tempString IS NOT NULL THEN
    state := split_part(tempString, ':', 1);
    result.stateAbbrev := split_part(tempString, ':', 2);
  END IF;

  IF debug_flag THEN
    raise notice '% stateAbbrev: %', clock_timestamp(), result.stateAbbrev;
  END IF;

  -- The easiest case is if the address is comma delimited.  There are some
  -- likely cases:
  --   street level, location, state
  --   street level, location state
  --   street level, location
  --   street level, internal address, location, state
  --   street level, internal address, location state
  --   street level, internal address location state
  --   street level, internal address, location
  --   street level, internal address location
  -- The first three are useful.

  tempString := substring(fullStreet, '(?i),' || ws || '+(.*?)(,?' || ws ||
      '*' || cull_null(state) || '$)');
  IF tempString = '' THEN tempString := NULL; END IF;
  IF tempString IS NOT NULL THEN
    IF tempString LIKE '%,%' THEN -- if it has a comma probably has suite, strip it from location
        result.location := trim(split_part(tempString,',',2));
    ELSE
        result.location := tempString;
    END IF;
    IF addressString IS NOT NULL THEN
      fullStreet := substring(fullStreet, '(?i)' || addressString || ws ||
          '+(.*),' || ws || '+' || result.location);
    ELSE
      fullStreet := substring(fullStreet, '(?i)(.*),' || ws || '+' ||
          result.location);
    END IF;
  END IF;

  IF debug_flag THEN
    raise notice '% fullStreet: %',  clock_timestamp(), fullStreet;
    raise notice '% location: %', clock_timestamp(), result.location;
  END IF;

  -- Pull out the full street information, defined as everything between the
  -- address and the state.  This includes the location.
  -- This doesn't need to be done if location has already been found.
  IF result.location IS NULL THEN
    IF addressString IS NOT NULL THEN
      IF state IS NOT NULL THEN
        fullStreet := substring(fullStreet, '(?i)' || addressString ||
            ws || '+(.*?)' || ws || '+' || state);
      ELSE
        fullStreet := substring(fullStreet, '(?i)' || addressString ||
            ws || '+(.*?)');
      END IF;
    ELSE
      IF state IS NOT NULL THEN
        fullStreet := substring(fullStreet, '(?i)(.*?)' || ws ||
            '+' || state);
      ELSE
        fullStreet := substring(fullStreet, '(?i)(.*?)');
      END IF;
    END IF;

    IF debug_flag THEN
      raise notice '% fullStreet: %', clock_timestamp(),fullStreet;
    END IF;

    IF debug_flag THEN
      raise notice '% start location extract', clock_timestamp();
    END IF;
    result.location := location_extract(fullStreet, result.stateAbbrev);

    IF debug_flag THEN
      raise notice '% end location extract', clock_timestamp();
    END IF;

    -- A location can't be a street type, sorry.
    IF lower(result.location) IN (SELECT lower(name) FROM street_type_lookup) THEN
        result.location := NULL;
    END IF;

    -- If the location was found, remove it from fullStreet
    IF result.location IS NOT NULL THEN
      fullStreet := substring(fullStreet, '(?i)(.*)' || ws || '+' ||
          result.location);
    END IF;
  END IF;

  IF debug_flag THEN
    raise notice 'fullStreet: %', fullStreet;
    raise notice 'location: %', result.location;
  END IF;

  -- Determine if any internal address is included, such as apartment
  -- or suite number.
  -- this count is surprisingly slow by itself but much faster if you add an ILIKE AND clause
  SELECT INTO tempInt count(*) FROM secondary_unit_lookup
      WHERE fullStreet ILIKE '%' || name || '%' AND texticregexeq(fullStreet, '(?i)' || ws || name || '('
          || ws || '|$)');
  IF tempInt = 1 THEN
    result.internal := substring(fullStreet, '(?i)' || ws || '('
        || name ||  ws || '*#?' || ws
        || '*(?:[0-9][-0-9a-zA-Z]*)?' || ')(?:' || ws || '|$)')
        FROM secondary_unit_lookup
        WHERE fullStreet ILIKE '%' || name || '%' AND texticregexeq(fullStreet, '(?i)' || ws || name || '('
        || ws || '|$)');
    ELSIF tempInt > 1 THEN
    -- In the event of multiple matches to a secondary unit designation, we
    -- will assume that the last one is the true one.
    tempInt := 0;
    FOR rec in SELECT trim(substring(fullStreet, '(?i)' || ws || '('
        || name || '(?:' || ws || '*#?' || ws
        || '*(?:[0-9][-0-9a-zA-Z]*)?)' || ws || '?|$)')) as value
        FROM secondary_unit_lookup
        WHERE fullStreet ILIKE '%' || name || '%' AND  texticregexeq(fullStreet, '(?i)' || ws || name || '('
        || ws || '|$)') LOOP
      IF tempInt < position(rec.value in fullStreet) THEN
        tempInt := position(rec.value in fullStreet);
        result.internal := rec.value;
      END IF;
    END LOOP;
  END IF;

  IF debug_flag THEN
    raise notice 'internal: %', result.internal;
  END IF;

  IF result.location IS NULL THEN
    -- If the internal address is given, the location is everything after it.
    result.location := trim(substring(fullStreet, result.internal || ws || '+(.*)$'));
  END IF;

  IF debug_flag THEN
    raise notice 'location: %', result.location;
  END IF;

  -- Pull potential street types from the full street information
  -- this count is surprisingly slow by itself but much faster if you add an ILIKE AND clause
  -- difference of 98ms vs 16 ms for example
  -- Put a space in front to make regex easier can always count on it starting with space
  -- Reject all street types where the fullstreet name is equal to the name
  fullStreet := ' ' || trim(fullStreet);
  tempInt := count(*) FROM street_type_lookup
      WHERE fullStreet ILIKE '%' || name || '%' AND
        trim(upper(fullStreet)) != name AND
        texticregexeq(fullStreet, '(?i)' || ws || '(' || name
      || ')(?:' || ws || '|$)');
  IF tempInt = 1 THEN
    SELECT INTO rec abbrev, substring(fullStreet, '(?i)' || ws || '('
        || name || ')(?:' || ws || '|$)') AS given, is_hw FROM street_type_lookup
        WHERE fullStreet ILIKE '%' || name || '%' AND
             trim(upper(fullStreet)) != name AND
            texticregexeq(fullStreet, '(?i)' || ws || '(' || name
        || ')(?:' || ws || '|$)')  ;
    streetType := rec.given;
    result.streetTypeAbbrev := rec.abbrev;
    isHighway :=  rec.is_hw;
    IF debug_flag THEN
    	   RAISE NOTICE 'street Type: %, street Type abbrev: %', rec.given, rec.abbrev;
    END IF;
  ELSIF tempInt > 1 THEN
    tempInt := 0;
    -- the last matching abbrev in the string is the most likely one
    FOR rec IN SELECT * FROM
    	(SELECT abbrev, name, substring(fullStreet, '(?i)' || ws || '?('
        || name || ')(?:' || ws || '|$)') AS given, is_hw ,
        		RANK() OVER( ORDER BY position(name IN upper(trim(fullStreet))) ) As n_start,
        		RANK() OVER( ORDER BY position(name IN upper(trim(fullStreet))) + length(name) ) As n_end,
        		COUNT(*) OVER() As nrecs, position(name IN upper(trim(fullStreet)))
        		FROM street_type_lookup
        WHERE fullStreet ILIKE '%' || name || '%'  AND
            trim(upper(fullStreet)) != name AND
            (texticregexeq(fullStreet, '(?i)' || ws || '(' || name
            -- we only consider street types that are regular and not at beginning of name or are highways (since those can be at beg or end)
            -- we take the one that is the longest e.g Country Road would be more correct than Road
        || ')(?:' || ws || '|$)') OR (is_hw AND fullstreet ILIKE name || ' %') )
     AND ((NOT is_hw AND position(name IN upper(trim(fullStreet))) > 1 OR is_hw) )
        ) As foo
        -- N_start - N_end - ensure we first get the one with the most overlapping sub types
        -- Then of those get the one that ends last and then starts first
        ORDER BY n_start - n_end, n_end DESC, n_start LIMIT 1  LOOP
      -- If we have found an internal address, make sure the type
      -- precedes it.
      /** TODO: I don't think we need a loop anymore since we are just returning one and the one in the last position
      * I'll leave for now though **/
      IF result.internal IS NOT NULL THEN
        IF position(rec.given IN fullStreet) < position(result.internal IN fullStreet) THEN
          IF tempInt < position(rec.given IN fullStreet) THEN
            streetType := rec.given;
            result.streetTypeAbbrev := rec.abbrev;
            isHighway := rec.is_hw;
            tempInt := position(rec.given IN fullStreet);
          END IF;
        END IF;
      ELSIF tempInt < position(rec.given IN fullStreet) THEN
        streetType := rec.given;
        result.streetTypeAbbrev := rec.abbrev;
        isHighway := rec.is_hw;
        tempInt := position(rec.given IN fullStreet);
        IF debug_flag THEN
        	RAISE NOTICE 'street Type: %, street Type abbrev: %', rec.given, rec.abbrev;
        END IF;
      END IF;
    END LOOP;
  END IF;

  IF debug_flag THEN
    raise notice '% streetTypeAbbrev: %', clock_timestamp(), result.streetTypeAbbrev;
  END IF;

  -- There is a little more processing required now.  If the word after the
  -- street type begins with a number, then its most likely a highway like State Route 225a.  If
  -- In Tiger 2010+ the reduced Street name just has the number
  -- the next word starts with a char, then everything after the street type
  -- will be considered location.  If there is no street type, then I'm sad.
  IF streetType IS NOT NULL THEN
    -- Check if the fullStreet contains the streetType and ends in just numbers
    -- If it does its a road number like a country road or state route or other highway
    -- Just set the number to be the name of street

    tempString := NULL;
    IF isHighway THEN
        tempString :=  substring(fullStreet, streetType || ws || '+' || E'([0-9a-zA-Z]+)' || ws || '*');
    END IF;
    IF tempString > '' AND result.location IS NOT NULL THEN
        reducedStreet := tempString;
        result.streetName := reducedStreet;
        IF debug_flag THEN
        	RAISE NOTICE 'reduced Street: %', result.streetName;
        END IF;
        -- the post direction might be portion of fullStreet after reducedStreet and type
		-- reducedStreet: 24  fullStreet: Country Road 24, N or fullStreet: Country Road 24 N
		tempString := regexp_replace(fullStreet, streetType || ws || '+' || reducedStreet,'');
		IF tempString > '' THEN
			IF debug_flag THEN
				RAISE NOTICE 'remove reduced street: % + streetType: % from fullstreet: %', reducedStreet, streetType, fullStreet;
			END IF;
			tempString := abbrev FROM direction_lookup WHERE
			 tempString ILIKE '%' || name || '%'  AND texticregexeq(reducedStreet || ws || '+' || streetType, '(?i)(' || name || ')' || ws || '+|$')
			 	ORDER BY length(name) DESC LIMIT 1;
			IF tempString IS NOT NULL THEN
				result.postDirAbbrev = trim(tempString);
				IF debug_flag THEN
					RAISE NOTICE 'postDirAbbre of highway: %', result.postDirAbbrev;
				END IF;
			END IF;
		END IF;
    ELSE
        tempString := substring(fullStreet, streetType || ws ||
            E'+([0-9][^ ,.\t\r\n\f]*?)' || ws);
        IF tempString IS NOT NULL THEN
          IF result.location IS NULL THEN
            result.location := substring(fullStreet, streetType || ws || '+'
                     || tempString || ws || '+(.*)$');
          END IF;
          reducedStreet := substring(fullStreet, '(.*)' || ws || '+'
                        || result.location || '$');
          streetType := NULL;
          result.streetTypeAbbrev := NULL;
        ELSE
          IF result.location IS NULL THEN
            result.location := substring(fullStreet, streetType || ws || '+(.*)$');
          END IF;
          reducedStreet := substring(fullStreet, '^(.*)' || ws || '+'
                        || streetType);
          IF COALESCE(trim(reducedStreet),'') = '' THEN --reduced street can't be blank
            reducedStreet := fullStreet;
            streetType := NULL;
            result.streetTypeAbbrev := NULL;
          END IF;
        END IF;
		-- the post direction might be portion of fullStreet after reducedStreet
		-- reducedStreet: Main  fullStreet: Main St, N or fullStreet: Main St N
		tempString := trim(regexp_replace(fullStreet,  reducedStreet ||  ws || '+' || streetType,''));
		IF tempString > '' THEN
		  tempString := abbrev FROM direction_lookup WHERE
			 tempString ILIKE '%' || name || '%'
			 AND texticregexeq(fullStreet || ' ', '(?i)' || reducedStreet || ws || '+' || streetType || ws || '+(' || name || ')' || ws || '+')
			ORDER BY length(name) DESC LIMIT 1;
		  IF tempString IS NOT NULL THEN
			result.postDirAbbrev = trim(tempString);
		  END IF;
		END IF;

		IF debug_flag THEN
			raise notice '% reduced street: %', clock_timestamp(), reducedStreet;
		END IF;

		-- The pre direction should be at the beginning of the fullStreet string.
		-- The post direction should be at the beginning of the location string
		-- if there is no internal address
		reducedStreet := trim(reducedStreet);
		tempString := trim(regexp_replace(fullStreet,  ws || '+' || reducedStreet ||  ws || '+',''));
		IF tempString > '' THEN
			tempString := substring(reducedStreet, '(?i)(^' || name
				|| ')' || ws) FROM direction_lookup WHERE
				 reducedStreet ILIKE '%' || name || '%'  AND texticregexeq(reducedStreet, '(?i)(^' || name || ')' || ws)
				ORDER BY length(name) DESC LIMIT 1;
		END IF;
		IF tempString > '' THEN
		  preDir := tempString;
		  result.preDirAbbrev := abbrev FROM direction_lookup
			  where reducedStreet ILIKE '%' || name '%' AND texticregexeq(reducedStreet, '(?i)(^' || name || ')' || ws)
			  ORDER BY length(name) DESC LIMIT 1;
		  result.streetName := trim(substring(reducedStreet, '^' || preDir || ws || '(.*)'));
		ELSE
		  result.streetName := trim(reducedStreet);
		END IF;
    END IF;
    IF texticregexeq(result.location, '(?i)' || result.internal || '$') THEN
      -- If the internal address is at the end of the location, then no
      -- location was given.  We still need to look for post direction.
      SELECT INTO rec abbrev,
          substring(result.location, '(?i)^(' || name || ')' || ws) as value
          FROM direction_lookup
            WHERE result.location ILIKE '%' || name || '%' AND texticregexeq(result.location, '(?i)^'
          || name || ws) ORDER BY length(name) desc LIMIT 1;
      IF rec.value IS NOT NULL THEN
        postDir := rec.value;
        result.postDirAbbrev := rec.abbrev;
      END IF;
      result.location := null;
    ELSIF result.internal IS NULL THEN
      -- If no location is given, the location string will be the post direction
      SELECT INTO tempInt count(*) FROM direction_lookup WHERE
          upper(result.location) = upper(name);
      IF tempInt != 0 THEN
        postDir := result.location;
        SELECT INTO result.postDirAbbrev abbrev FROM direction_lookup WHERE
            upper(postDir) = upper(name);
        result.location := NULL;

        IF debug_flag THEN
            RAISE NOTICE '% postDir exact match: %', clock_timestamp(), result.postDirAbbrev;
        END IF;
      ELSE
        -- postDirection is not equal location, but may be contained in it
        -- It is only considered a postDirection if it is not preceded by a ,
        SELECT INTO tempString substring(result.location, '(?i)(^' || name
            || ')' || ws) FROM direction_lookup WHERE
            result.location ILIKE '%' || name || '%' AND texticregexeq(result.location, '(?i)(^' || name || ')' || ws)
            	AND NOT  texticregexeq(rawInput, '(?i)(,' || ws || '+' || result.location || ')' || ws)
            ORDER BY length(name) desc LIMIT 1;

        IF debug_flag THEN
            RAISE NOTICE '% location trying to extract postdir: %, tempstring: %, rawInput: %', clock_timestamp(), result.location, tempString, rawInput;
        END IF;
        IF tempString IS NOT NULL THEN
            postDir := tempString;
            SELECT INTO result.postDirAbbrev abbrev FROM direction_lookup
              WHERE result.location ILIKE '%' || name || '%' AND texticregexeq(result.location, '(?i)(^' || name || ')' || ws) ORDER BY length(name) DESC LIMIT 1;
              result.location := substring(result.location, '^' || postDir || ws || '+(.*)');
            IF debug_flag THEN
                  RAISE NOTICE '% postDir: %', clock_timestamp(), result.postDirAbbrev;
            END IF;
        END IF;

      END IF;
    ELSE
      -- internal is not null, but is not at the end of the location string
      -- look for post direction before the internal address
        IF debug_flag THEN
            RAISE NOTICE '%fullstreet before extract postdir: %', clock_timestamp(), fullStreet;
        END IF;
        SELECT INTO tempString substring(fullStreet, '(?i)' || streetType
          || ws || '+(' || name || ')' || ws || '+' || result.internal)
          FROM direction_lookup
          WHERE fullStreet ILIKE '%' || name || '%' AND texticregexeq(fullStreet, '(?i)'
          || ws || name || ws || '+' || result.internal) ORDER BY length(name) desc LIMIT 1;
        IF tempString IS NOT NULL THEN
            postDir := tempString;
            SELECT INTO result.postDirAbbrev abbrev FROM direction_lookup
                WHERE texticregexeq(fullStreet, '(?i)' || ws || name || ws);
        END IF;
    END IF;
  ELSE
  -- No street type was found

    -- If an internal address was given, then the split becomes easy, and the
    -- street name is everything before it, without directions.
    IF result.internal IS NOT NULL THEN
      reducedStreet := substring(fullStreet, '(?i)^(.*?)' || ws || '+'
                    || result.internal);
      tempInt := count(*) FROM direction_lookup WHERE
          reducedStreet ILIKE '%' || name || '%' AND texticregexeq(reducedStreet, '(?i)' || ws || name || '$');
      IF tempInt > 0 THEN
        postDir := substring(reducedStreet, '(?i)' || ws || '('
            || name || ')' || '$') FROM direction_lookup
            WHERE reducedStreet ILIKE '%' || name || '%' AND texticregexeq(reducedStreet, '(?i)' || ws || name || '$');
        result.postDirAbbrev := abbrev FROM direction_lookup
            WHERE texticregexeq(reducedStreet, '(?i)' || ws || name || '$');
      END IF;
      tempString := substring(reducedStreet, '(?i)^(' || name
          || ')' || ws) FROM direction_lookup WHERE
           reducedStreet ILIKE '%' || name || '%' AND texticregexeq(reducedStreet, '(?i)^(' || name || ')' || ws)
          ORDER BY length(name) DESC;
      IF tempString IS NOT NULL THEN
        preDir := tempString;
        result.preDirAbbrev := abbrev FROM direction_lookup WHERE
             reducedStreet ILIKE '%' || name || '%' AND texticregexeq(reducedStreet, '(?i)(^' || name || ')' || ws)
            ORDER BY length(name) DESC;
        result.streetName := substring(reducedStreet, '(?i)^' || preDir || ws
                   || '+(.*?)(?:' || ws || '+' || cull_null(postDir) || '|$)');
      ELSE
        result.streetName := substring(reducedStreet, '(?i)^(.*?)(?:' || ws
                   || '+' || cull_null(postDir) || '|$)');
      END IF;
    ELSE

      -- If a post direction is given, then the location is everything after,
      -- the street name is everything before, less any pre direction.
      fullStreet := trim(fullStreet);
      tempInt := count(*) FROM direction_lookup
          WHERE fullStreet ILIKE '%' || name || '%' AND texticregexeq(fullStreet, '(?i)' || ws || name || '(?:'
              || ws || '|$)');

      IF tempInt = 1 THEN
        -- A single postDir candidate was found.  This makes it easier.
        postDir := substring(fullStreet, '(?i)' || ws || '('
            || name || ')(?:' || ws || '|$)') FROM direction_lookup WHERE
             fullStreet ILIKE '%' || name || '%' AND texticregexeq(fullStreet, '(?i)' || ws || name || '(?:'
            || ws || '|$)');
        result.postDirAbbrev := abbrev FROM direction_lookup
            WHERE fullStreet ILIKE '%' || name || '%' AND texticregexeq(fullStreet, '(?i)' || ws || name
            || '(?:' || ws || '|$)');
        IF result.location IS NULL THEN
          result.location := substring(fullStreet, '(?i)' || ws || postDir
                   || ws || '+(.*?)$');
        END IF;
        reducedStreet := substring(fullStreet, '^(.*?)' || ws || '+'
                      || postDir);
        tempString := substring(reducedStreet, '(?i)(^' || name
            || ')' || ws) FROM direction_lookup
            WHERE
                reducedStreet ILIKE '%' || name || '%' AND texticregexeq(reducedStreet, '(?i)(^' || name || ')' || ws)
            ORDER BY length(name) DESC;
        IF tempString IS NOT NULL THEN
          preDir := tempString;
          result.preDirAbbrev := abbrev FROM direction_lookup WHERE
              reducedStreet ILIKE '%' || name || '%' AND texticregexeq(reducedStreet, '(?i)(^' || name || ')' || ws)
              ORDER BY length(name) DESC;
          result.streetName := trim(substring(reducedStreet, '^' || preDir || ws
                     || '+(.*)'));
        ELSE
          result.streetName := trim(reducedStreet);
        END IF;
      ELSIF tempInt > 1 THEN
        -- Multiple postDir candidates were found.  We need to find the last
        -- incident of a direction, but avoid getting the last word from
        -- a two word direction. eg extracting "East" from "North East"
        -- We do this by sorting by length, and taking the last direction
        -- in the results that is not included in an earlier one.
        -- This won't be a problem it preDir is North East and postDir is
        -- East as the regex requires a space before the direction.  Only
        -- the East will return from the preDir.
        tempInt := 0;
        FOR rec IN SELECT abbrev, substring(fullStreet, '(?i)' || ws || '('
            || name || ')(?:' || ws || '|$)') AS value
            FROM direction_lookup
            WHERE fullStreet ILIKE '%' || name || '%' AND texticregexeq(fullStreet, '(?i)' || ws || name
            || '(?:' || ws || '|$)')
            ORDER BY length(name) desc LOOP
          tempInt := 0;
          IF tempInt < position(rec.value in fullStreet) THEN
            IF postDir IS NULL THEN
              tempInt := position(rec.value in fullStreet);
              postDir := rec.value;
              result.postDirAbbrev := rec.abbrev;
            ELSIF NOT texticregexeq(postDir, '(?i)' || rec.value) THEN
              tempInt := position(rec.value in fullStreet);
              postDir := rec.value;
              result.postDirAbbrev := rec.abbrev;
             END IF;
          END IF;
        END LOOP;
        IF result.location IS NULL THEN
          result.location := substring(fullStreet, '(?i)' || ws || postDir || ws
                   || '+(.*?)$');
        END IF;
        reducedStreet := substring(fullStreet, '(?i)^(.*?)' || ws || '+'
                      || postDir);
        SELECT INTO tempString substring(reducedStreet, '(?i)(^' || name
            || ')' || ws) FROM direction_lookup WHERE
             reducedStreet ILIKE '%' || name || '%' AND  texticregexeq(reducedStreet, '(?i)(^' || name || ')' || ws)
            ORDER BY length(name) DESC;
        IF tempString IS NOT NULL THEN
          preDir := tempString;
          SELECT INTO result.preDirAbbrev abbrev FROM direction_lookup WHERE
              reducedStreet ILIKE '%' || name || '%' AND  texticregexeq(reducedStreet, '(?i)(^' || name || ')' || ws)
              ORDER BY length(name) DESC;
          result.streetName := substring(reducedStreet, '^' || preDir || ws
                     || '+(.*)');
        ELSE
          result.streetName := reducedStreet;
        END IF;
      ELSE

        -- There is no street type, directional suffix or internal address
        -- to allow distinction between street name and location.
        IF result.location IS NULL THEN
          IF debug_flag THEN
            raise notice 'fullStreet: %', fullStreet;
          END IF;

          result.location := location_extract(fullStreet, result.stateAbbrev);
          -- If the location was found, remove it from fullStreet
          IF result.location IS NOT NULL THEN
            fullStreet := substring(fullStreet, '(?i)(.*),' || ws || '+' ||
                result.location);
          END IF;
        END IF;

        -- Check for a direction prefix.
        SELECT INTO tempString substring(fullStreet, '(?i)(^' || name
            || ')' || ws) FROM direction_lookup WHERE
            texticregexeq(fullStreet, '(?i)(^' || name || ')' || ws)
            ORDER BY length(name);
        IF tempString IS NOT NULL THEN
          preDir := tempString;
          SELECT INTO result.preDirAbbrev abbrev FROM direction_lookup WHERE
              texticregexeq(fullStreet, '(?i)(^' || name || ')' || ws)
              ORDER BY length(name) DESC;
          IF result.location IS NOT NULL THEN
            -- The location may still be in the fullStreet, or may
            -- have been removed already
            result.streetName := substring(fullStreet, '^' || preDir || ws
                       || '+(.*?)(' || ws || '+' || result.location || '|$)');
          ELSE
            result.streetName := substring(fullStreet, '^' || preDir || ws
                       || '+(.*?)' || ws || '*');
          END IF;
        ELSE
          IF result.location IS NOT NULL THEN
            -- The location may still be in the fullStreet, or may
            -- have been removed already
            result.streetName := substring(fullStreet, '^(.*?)(' || ws
                       || '+' || result.location || '|$)');
          ELSE
            result.streetName := fullStreet;
          END IF;
        END IF;
      END IF;
    END IF;
  END IF;

 -- For address number only put numbers and stop if reach a non-number e.g. 123-456 will return 123
  result.address := to_number(substring(addressString, '[0-9]+'),  '99999999');
   --get rid of extraneous spaces before we return
  result.zip := trim(zipString);
  result.streetName := trim(result.streetName);
  result.location := trim(result.location);
  result.postDirAbbrev := trim(result.postDirAbbrev);
  result.parsed := TRUE;
  RETURN result;
END
$$
  LANGUAGE plpgsql IMMUTABLE STRICT
  COST 100;
-- helper function to determine if street type
-- should be put before or after the street name
-- note in streettype lookup this is misnamed as is_hw
-- because I originally thought only highways had that behavior
-- it applies to foreign influenced roads like Camino (for road)
CREATE OR REPLACE FUNCTION is_pretype(text) RETURNS boolean AS
$$
    SELECT EXISTS(SELECT name FROM street_type_lookup WHERE upper(name) = upper($1) AND is_hw );
$$
LANGUAGE sql IMMUTABLE STRICT; /** I know this should be stable but it's practically immutable :) **/

CREATE OR REPLACE FUNCTION pprint_addy(
    input NORM_ADDY
) RETURNS VARCHAR
AS $_$
DECLARE
  result VARCHAR;
BEGIN
  IF NOT input.parsed THEN
    RETURN NULL;
  END IF;

  result := COALESCE(input.address_alphanumeric, cull_null(input.address::text))
         || COALESCE(' ' || input.preDirAbbrev, '')
         || CASE WHEN is_pretype(input.streetTypeAbbrev) THEN ' ' || input.streetTypeAbbrev  ELSE '' END
         || COALESCE(' ' || input.streetName, '')
         || CASE WHEN NOT is_pretype(input.streetTypeAbbrev) THEN ' ' || input.streetTypeAbbrev  ELSE '' END
         || COALESCE(' ' || input.postDirAbbrev, '')
         || CASE WHEN
              input.address IS NOT NULL OR
              input.streetName IS NOT NULL
              THEN ', ' ELSE '' END
         || cull_null(input.internal)
         || CASE WHEN input.internal IS NOT NULL THEN ', ' ELSE '' END
         || cull_null(input.location)
         || CASE WHEN input.location IS NOT NULL THEN ', ' ELSE '' END
         || COALESCE(input.stateAbbrev || ' ' , '')
         || cull_null(input.zip) || COALESCE('-' || input.zip4, '');

  RETURN trim(result);

END;
$_$ LANGUAGE plpgsql IMMUTABLE;
--  Lookup tables used by pagc to standardize in format expected by tiger geocoder
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT tiger.SetSearchPathForInstall('tiger');
CREATE OR REPLACE FUNCTION install_pagc_tables()
	RETURNS void AS
$$
DECLARE var_temp text;
BEGIN
	var_temp := tiger.SetSearchPathForInstall('tiger'); /** set set search path to have tiger in front **/
	IF NOT EXISTS(SELECT table_name FROM information_schema.columns WHERE table_schema = 'tiger' AND table_name = 'pagc_gaz')  THEN
		CREATE TABLE pagc_gaz (id serial NOT NULL primary key ,seq integer ,word text, stdword text, token integer,is_custom boolean NOT NULL default true);
		GRANT SELECT ON pagc_gaz TO public;
	END IF;
	IF NOT EXISTS(SELECT table_name FROM information_schema.columns WHERE table_schema = 'tiger' AND table_name = 'pagc_lex')  THEN
		CREATE TABLE pagc_lex (id serial NOT NULL primary key,seq integer,word text,stdword text,token integer,is_custom boolean NOT NULL default true);
		GRANT SELECT ON pagc_lex TO public;
	END IF;
	IF NOT EXISTS(SELECT table_name FROM information_schema.columns WHERE table_schema = 'tiger' AND table_name = 'pagc_rules')  THEN
		CREATE TABLE pagc_rules (id serial NOT NULL primary key,rule text, is_custom boolean DEFAULT true);
		GRANT SELECT ON pagc_rules TO public;
	END IF;
	IF NOT EXISTS(SELECT table_name FROM information_schema.columns WHERE table_schema = 'tiger' AND table_name = 'pagc_gaz' AND data_type='text')  THEN
	-- its probably old table structure change type of lex and gaz columns
		ALTER TABLE tiger.pagc_lex ALTER COLUMN word TYPE text;
		ALTER TABLE tiger.pagc_lex ALTER COLUMN stdword TYPE text;
		ALTER TABLE tiger.pagc_gaz ALTER COLUMN word TYPE text;
		ALTER TABLE tiger.pagc_gaz ALTER COLUMN stdword TYPE text;
	END IF;
	IF NOT EXISTS(SELECT table_name FROM information_schema.columns WHERE table_schema = 'tiger' AND table_name = 'pagc_rules' AND column_name = 'is_custom' )  THEN
	-- its probably old table structure add column
		ALTER TABLE tiger.pagc_rules ADD COLUMN is_custom boolean NOT NULL DEFAULT false;
	END IF;
END;
$$
language plpgsql;

SELECT install_pagc_tables();
DELETE FROM pagc_gaz WHERE is_custom = false;
DELETE FROM pagc_lex WHERE is_custom = false;
DELETE FROM pagc_rules WHERE is_custom = false OR id < 10000;

INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (1, 1, 'AB', 'ALBERTA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (2, 2, 'AB', 'ALBERTA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (3, 3, 'AB', 'ALBERTA', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (4, 1, 'AFB', 'AIR FORCE BASE', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (5, 1, 'A F B', 'AIR FORCE BASE', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (6, 1, 'AIR FORCE BASE', 'AIR FORCE BASE', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (8, 2, 'AK', 'ALASKA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (11, 2, 'AL', 'ALABAMA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (14, 2, 'ALA', 'ALABAMA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (17, 2, 'ALABAMA', 'ALABAMA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (19, 2, 'ALASKA', 'ALASKA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (20, 1, 'ALBERTA', 'ALBERTA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (21, 2, 'ALBERTA', 'ALBERTA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (23, 2, 'AR', 'ARKANSAS', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (26, 2, 'ARIZ', 'ARIZONA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (29, 2, 'ARIZONA', 'ARIZONA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (31, 2, 'ARK', 'ARKANSAS', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (34, 2, 'ARKANSAS', 'ARKANSAS', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (36, 2, 'AZ', 'ARIZONA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (38, 1, 'B C', 'BRITISH COLUMBIA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (39, 2, 'B C', 'BRITISH COLUMBIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (40, 3, 'B C', 'BRITISH COLUMBIA', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (41, 1, 'BC', 'BRITISH COLUMBIA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (42, 2, 'BC', 'BRITISH COLUMBIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (43, 3, 'BC', 'BRITISH COLUMBIA', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (44, 1, 'BRITISH COLUMBIA', 'BRITISH COLUMBIA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (45, 2, 'BRITISH COLUMBIA', 'BRITISH COLUMBIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (47, 2, 'CA', 'CALIFORNIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (49, 4, 'CA', 'CANADA', 12, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (50, 5, 'CA', 'CARRE', 2, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (52, 2, 'CALIF', 'CALIFORNIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (55, 2, 'CALIFORNIA', 'CALIFORNIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (56, 1, 'CANADA', 'CANADA', 12, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (57, 2, 'CANADA', 'CANADA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (59, 2, 'CO', 'COLORADO', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (61, 1, 'COLOMBIE BRITANNIQUE', 'BRITISH COLUMBIA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (62, 2, 'COLOMBIE BRITANNIQUE', 'BRITISH COLUMBIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (64, 2, 'COLORADO', 'COLORADO', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (66, 2, 'CONN', 'CONNECTICUT', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (69, 2, 'CONNECTICUT', 'CONNECTICUT', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (71, 2, 'CT', 'CONNECTICUT', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (74, 2, 'DC', 'DC', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (77, 3, 'DE', 'DELAWARE', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (79, 2, 'DEL', 'DELAWARE', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (82, 2, 'DELAWARE', 'DELAWARE', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (84, 2, 'DC', 'DISTRICT OF COLUMBIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (85, 2, 'EL PASO', 'EL PASO', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (87, 2, 'FL', 'FLORIDA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (90, 2, 'FLA', 'FLORIDA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (93, 2, 'FLORIDA', 'FLORIDA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (94, 1, 'FRKS', 'FORKS', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (96, 2, 'GA', 'GEORGIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (99, 2, 'GEORGIA', 'GEORGIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (101, 2, 'HAWAII', 'HAWAII', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (103, 2, 'HI', 'HAWAII', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (106, 2, 'IA', 'IOWA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (109, 2, 'ID', 'IDAHO', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (112, 2, 'IDAHO', 'IDAHO', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (114, 2, 'IL', 'ILLINOIS', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (116, 1, 'ILE DU PRINCE EDOUARD', 'PRINCE EDWARD ISLAND', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (117, 2, 'ILE DU PRINCE EDOUARD', 'PRINCE EDWARD ISLAND', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (119, 2, 'ILL', 'ILLINOIS', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (122, 2, 'ILLINOIS', 'ILLINOIS', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (124, 2, 'IN', 'INDIANA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (127, 2, 'IND', 'INDIANA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (130, 2, 'INDIANA', 'INDIANA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (132, 2, 'IOWA', 'IOWA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (134, 2, 'KANSAS', 'KANSAS', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (136, 2, 'KENT', 'KENTUCKY', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (139, 2, 'KENTUCKY', 'KENTUCKY', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (141, 2, 'KS', 'KANSAS', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (144, 2, 'KY', 'KENTUCKY', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (147, 2, 'LA', 'LOUISIANA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (149, 1, 'LABRADOR', 'NEWFOUNDLAND AND LABRADOR', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (150, 2, 'LABRADOR', 'NEWFOUNDLAND AND LABRADOR', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (152, 2, 'LOUISIANA', 'LOUISIANA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (154, 2, 'MA', 'MASSACHUSETTS', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (156, 4, 'MA', 'MANOR', 2, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (158, 2, 'MAINE', 'MAINE', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (159, 1, 'MANITOBA', 'MANITOBA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (160, 2, 'MANITOBA', 'MANITOBA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (162, 2, 'MARYLAND', 'MARYLAND', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (164, 2, 'MASS', 'MASSACHUSETTS', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (167, 2, 'MASSACHUSETTS', 'MASSACHUSETTS', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (168, 1, 'MB', 'MANITOBA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (169, 2, 'MB', 'MANITOBA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (170, 3, 'MB', 'MANITOBA', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (172, 2, 'MD', 'MARYLAND', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (175, 2, 'ME', 'MAINE', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (178, 2, 'MI', 'MICHIGAN', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (181, 2, 'MICH', 'MICHIGAN', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (184, 2, 'MICHIGAN', 'MICHIGAN', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (186, 2, 'MINN', 'MINNESOTA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (189, 2, 'MINNESOTA', 'MINNESOTA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (191, 2, 'MISSISSIPPI', 'MISSISSIPPI', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (193, 2, 'MISSOURI', 'MISSOURI', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (195, 2, 'MN', 'MINNESOTA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (198, 2, 'MO', 'MISSOURI', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (201, 2, 'MONT', 'MONTANA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (204, 2, 'MONTANA', 'MONTANA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (206, 2, 'MT', 'MONTANA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (209, 2, 'MS', 'MISSISSIPPI', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (212, 2, 'N CAROLINA', 'NORTH CAROLINA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (214, 2, 'N DAKOTA', 'NORTH DAKOTA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (215, 1, 'NB', 'NEW BRUNSWICK', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (216, 2, 'NB', 'NEW BRUNSWICK', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (217, 3, 'NB', 'NEW BRUNSWICK', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (219, 2, 'NC', 'NORTH CAROLINA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (222, 2, 'ND', 'NORTH DAKOTA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (225, 2, 'NE', 'NEBRASKA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (228, 2, 'NEB', 'NEBRASKA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (231, 2, 'NEBRASKA', 'NEBRASKA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (233, 2, 'NEV', 'NEVADA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (236, 2, 'NEVADA', 'NEVADA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (237, 1, 'NEW BRUNSWICK', 'NEW BRUNSWICK', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (238, 2, 'NEW BRUNSWICK', 'NEW BRUNSWICK', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (240, 2, 'NEW HAMPSHIRE', 'NEW HAMPSHIRE', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (242, 2, 'NEW JERSEY', 'NEW JERSEY', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (244, 2, 'NEW MEXICO', 'NEW MEXICO', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (246, 2, 'NEW YORK', 'NEW YORK', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (247, 1, 'NEWFOUNDLAND', 'NEWFOUNDLAND AND LABRADOR', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (248, 2, 'NEWFOUNDLAND', 'NEWFOUNDLAND AND LABRADOR', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (249, 1, 'NF', 'NEWFOUNDLAND AND LABRADOR', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (250, 2, 'NF', 'NEWFOUNDLAND AND LABRADOR', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (251, 3, 'NF', 'NEWFOUNDLAND AND LABRADOR', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (253, 2, 'NH', 'NEW HAMPSHIRE', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (256, 2, 'NJ', 'NEW JERSEY', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (258, 1, 'NL', 'NEWFOUNDLAND AND LABRADOR', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (259, 2, 'NL', 'NEWFOUNDLAND AND LABRADOR', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (260, 3, 'NL', 'NEWFOUNDLAND AND LABRADOR', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (262, 2, 'NM', 'NEW MEXICO', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (265, 2, 'NORTH CAROLINA', 'NORTH CAROLINA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (267, 2, 'NORTH DAKOTA', 'NORTH DAKOTA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (268, 1, 'NORTHWEST', 'NORTHWEST', 22, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (269, 1, 'NORTHWEST TERRITORIES', 'NORTHWEST TERRITORIES', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (270, 2, 'NORTHWEST TERRITORIES', 'NORTHWEST TERRITORIES', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (271, 1, 'NOUVEAU BRUNSWICK', 'NEW BRUNSWICK', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (272, 2, 'NOUVEAU BRUNSWICK', 'NEW BRUNSWICK', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (273, 1, 'NOUVELLE ECOSSE', 'NOVA SCOTIA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (274, 2, 'NOUVELLE ECOSSE', 'NOVA SCOTIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (275, 1, 'NOVA SCOTIA', 'NOVA SCOTIA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (276, 2, 'NOVA SCOTIA', 'NOVA SCOTIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (277, 1, 'NS', 'NOVA SCOTIA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (278, 2, 'NS', 'NOVA SCOTIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (279, 3, 'NS', 'NOVA SCOTIA', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (280, 1, 'NT', 'NORTHWEST TERRITORIES', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (281, 2, 'NT', 'NORTHWEST TERRITORIES', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (282, 3, 'NT', 'NORTHWEST TERRITORIES', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (283, 1, 'NU', 'NUNAVUT', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (284, 2, 'NU', 'NUNAVUT', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (285, 3, 'NU', 'NUNAVUT', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (286, 1, 'NUNAVUT', 'NUNAVUT', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (287, 2, 'NUNAVUT', 'NUNAVUT', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (289, 2, 'NV', 'NEVADA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (292, 2, 'NY', 'NEW YORK', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (295, 2, 'OH', 'OHIO', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (298, 2, 'OHIO', 'OHIO', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (300, 2, 'OK', 'OKLAHOMA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (303, 2, 'OKLA', 'OKLAHOMA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (306, 2, 'OKLAHOMA', 'OKLAHOMA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (307, 1, 'ON', 'ONTARIO', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (308, 2, 'ON', 'ONTARIO', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (309, 3, 'ON', 'ONTARIO', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (310, 1, 'ONT', 'ONTARIO', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (311, 2, 'ONT', 'ONTARIO', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (312, 3, 'ONT', 'ONTARIO', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (313, 1, 'ONTARIO', 'ONTARIO', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (314, 2, 'ONTARIO', 'ONTARIO', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (316, 2, 'OR', 'OREGON', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (319, 2, 'ORE', 'OREGON', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (322, 2, 'OREGON', 'OREGON', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (324, 2, 'PA', 'PENNSYLVANIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (326, 1, 'PE', 'PRINCE EDWARD ISLAND', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (327, 2, 'PE', 'PRINCE EDWARD ISLAND', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (328, 3, 'PE', 'PRINCE EDWARD ISLAND', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (329, 1, 'PEI', 'PRINCE EDWARD ISLAND', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (330, 2, 'PEI', 'PRINCE EDWARD ISLAND', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (331, 3, 'PEI', 'PRINCE EDWARD ISLAND', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (333, 2, 'PENN', 'PENNSYLVANIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (336, 2, 'PENNA', 'PENNSYLVANIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (339, 2, 'PENNSYLVANIA', 'PENNSYLVANIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (340, 1, 'PQ', 'QUEBEC', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (341, 2, 'PQ', 'QUEBEC', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (342, 3, 'PQ', 'QUEBEC', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (344, 2, 'PR', 'PUERTO RICO', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (346, 1, 'PRINCE EDWARD ISLAND', 'PRINCE EDWARD ISLAND', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (347, 2, 'PRINCE EDWARD ISLAND', 'PRINCE EDWARD ISLAND', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (349, 2, 'PUERTO RICO', 'PUERTO RICO', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (350, 1, 'QC', 'QUEBEC', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (351, 2, 'QC', 'QUEBEC', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (352, 3, 'QC', 'QUEBEC', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (353, 1, 'QUEBEC', 'QUEBEC', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (354, 2, 'QUEBEC', 'QUEBEC', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (356, 2, 'RHODE ISLAND', 'RHODE ISLAND', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (358, 2, 'RI', 'RHODE ISLAND', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (361, 2, 'S CAROLINA', 'SOUTH CAROLINA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (363, 2, 'S DAKOTA', 'SOUTH DAKOTA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (364, 1, 'SASK', 'SASKATCHEWAN', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (365, 2, 'SASK', 'SASKATCHEWAN', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (366, 1, 'SASKATCHEWAN', 'SASKATCHEWAN', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (367, 2, 'SASKATCHEWAN', 'SASKATCHEWAN', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (369, 2, 'SC', 'SOUTH CAROLINA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (372, 2, 'SD', 'SOUTH DAKOTA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (374, 1, 'SK', 'SASKATCHEWAN', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (375, 2, 'SK', 'SASKATCHEWAN', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (376, 3, 'SK', 'SASKATCHEWAN', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (378, 2, 'SOUTH CAROLINA', 'SOUTH CAROLINA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (380, 2, 'SOUTH DAKOTA', 'SOUTH DAKOTA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (382, 2, 'TENN', 'TENNESSEE', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (385, 2, 'TENNESSEE', 'TENNESSEE', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (386, 1, 'TERRE NEUVE', 'NEWFOUNDLAND', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (387, 2, 'TERRE NEUVE', 'NEWFOUNDLAND', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (388, 1, 'TERRITOIRES DU NORD OUES', 'NORTHWEST TERRITORIES', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (389, 2, 'TERRITOIRES DU NORD OUES', 'NORTHWEST TERRITORIES', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (391, 2, 'TEX', 'TEXAS', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (394, 2, 'TEXAS', 'TEXAS', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (396, 2, 'TN', 'TENNESSEE', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (399, 2, 'TX', 'TEXAS', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (401, 2, 'U S', 'US', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (402, 3, 'U S', 'USA', 12, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (403, 1, 'U S A', 'USA', 12, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (404, 1, 'UNITED STATES OF AMERICA', 'USA', 12, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (405, 2, 'US', 'US', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (406, 3, 'US', 'USA', 12, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (407, 1, 'USA', 'USA', 12, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (409, 2, 'UT', 'UTAH', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (412, 2, 'UTAH', 'UTAH', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (414, 2, 'VA', 'VIRGINIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (417, 2, 'VERMONT', 'VERMONT', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (419, 2, 'VIRGINIA', 'VIRGINIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (421, 2, 'VT', 'VERMONT', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (424, 2, 'W VIRGINIA', 'WEST VIRGINIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (426, 2, 'WA', 'WASHINGTON', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (429, 2, 'WASH', 'WASHINGTON', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (432, 2, 'WASHINGTON', 'WASHINGTON', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (434, 2, 'WEST VIRGINIA', 'WEST VIRGINIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (436, 2, 'WI', 'WISCONSIN', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (439, 2, 'WISC', 'WISCONSIN', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (442, 2, 'WISCONSIN', 'WISCONSIN', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (444, 2, 'WV', 'WEST VIRGINIA', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (447, 2, 'WY', 'WYOMING', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (450, 2, 'WYOMING', 'WYOMING', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (451, 1, 'YK', 'YUKON', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (452, 2, 'YK', 'YUKON', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (453, 3, 'YK', 'YUKON', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (454, 1, 'YT', 'YUKON', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (455, 2, 'YT', 'YUKON', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (456, 3, 'YT', 'YUKON', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (457, 1, 'YUKON', 'YUKON', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (458, 2, 'YUKON', 'YUKON', 1, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (459, 1, 'BOIS D ARC', 'BOIS D ARC', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (460, 1, 'BOIS D''ARC', 'BOIS D ARC', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (461, 1, 'CAMP H M SMITH', 'CAMP H M SMITH', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (462, 1, 'CAMP HM SMITH', 'CAMP H M SMITH', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (463, 1, 'COEUR D ALENE', 'COEUR D ALENE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (464, 1, 'COEUR D''ALENE', 'COEUR D ALENE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (465, 1, 'D HANIS', 'D HANIS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (466, 1, 'D''HANIS', 'D HANIS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (467, 1, 'EL PASO', 'EL PASO', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (468, 1, 'FORT GEORGE G MEADE', 'FORT GEORGE G MEADE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (469, 1, 'FORT GEORGE MEADE', 'FORT GEORGE G MEADE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (470, 1, 'FORT MEADE', 'FORT GEORGE G MEADE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (471, 1, 'LAND O LAKES', 'LAND O LAKES', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (472, 1, 'LAND O''LAKES', 'LAND O LAKES', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (473, 1, 'M C B H KANEOHE BAY', 'M C B H KANEOHE BAY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (474, 1, 'MCBH KANEOHE BAY', 'M C B H KANEOHE BAY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (475, 1, 'N VAN', 'NORTH VANCOUVER', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (476, 1, 'N VANCOUVER', 'NORTH VANCOUVER', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (477, 1, 'NO VANCOUVER', 'NORTH VANCOUVER', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (478, 1, 'NORTH VANCOUVER', 'NORTH VANCOUVER', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (479, 1, 'O BRIEN', 'O BRIEN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (480, 1, 'O''BRIEN', 'O BRIEN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (481, 1, 'O FALLON', 'O FALLON', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (482, 1, 'O''FALLON', 'O FALLON', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (483, 1, 'O NEALS', 'O NEALS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (484, 1, 'O''NEALS', 'O NEALS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (485, 1, 'ROUND O', 'ROUND O', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (486, 1, 'S COFFEYVILLE', 'SOUTH COFFEYVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (487, 1, 'SOUTH COFFEYVILLE', 'SOUTH COFFEYVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (488, 1, 'U S A F ACADEMY', 'U S A F ACADEMY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (489, 1, 'USAF ACADEMY', 'U S A F ACADEMY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (490, 1, 'W VAN', 'WEST VANCOUVER', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (491, 1, 'W VANCOUVER', 'WEST VANCOUVER', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (492, 1, 'WEST VANCOUVER', 'WEST VANCOUVER', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (493, 1, 'AU GRES', 'AU GRES', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (494, 1, 'AU SABLE FORKS', 'AU SABLE FORKS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (495, 1, 'AU SABLE FRKS', 'AU SABLE FORKS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (496, 1, 'AU TRAIN', 'AU TRAIN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (497, 1, 'AVON BY THE SEA', 'AVON BY THE SEA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (498, 1, 'AVON BY SEA', 'AVON BY THE SEA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (499, 1, 'BAYOU LA BATRE', 'BAYOU LA BATRE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (500, 1, 'BIRD IN HAND', 'BIRD IN HAND', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (501, 1, 'CAMDEN ON GAULEY', 'CAMDEN ON GAULEY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (502, 1, 'CARDIFF BY THE SEA', 'CARDIFF BY THE SEA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (503, 1, 'CARDIFF BY SEA', 'CARDIFF BY THE SEA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (504, 1, 'CASTLETON ON HUDSON', 'CASTLETON ON HUDSON', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (505, 1, 'CAVE IN ROCK', 'CAVE IN ROCK', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (506, 1, 'CORNWALL ON HUDSON', 'CORNWALL ON HUDSON', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (507, 1, 'CROTON ON HUDSON', 'CROTON ON HUDSON', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (508, 1, 'DE BEQUE', 'DE BEQUE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (509, 1, 'DE BERRY', 'DE BERRY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (510, 1, 'DE FOREST', 'DE FOREST', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (511, 1, 'DE GRAFF', 'DE GRAFF', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (512, 1, 'DE KALB', 'DE KALB', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (513, 1, 'DE KALB JUNCTION', 'DE KALB JUNCTION', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (514, 1, 'DE LAND', 'DE LAND', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (515, 1, 'DE LEON', 'DE LEON', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (516, 1, 'DE LEON SPRINGS', 'DE LEON SPRINGS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (517, 1, 'DE MOSSVILLE', 'DE MOSSVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (518, 1, 'DE PERE', 'DE PERE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (519, 1, 'DE PEYSTER', 'DE PEYSTER', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (520, 1, 'DE QUEEN', 'DE QUEEN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (521, 1, 'DE RUYTER', 'DE RUYTER', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (522, 1, 'DE SMET', 'DE SMET', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (523, 1, 'DE SOTO', 'DE SOTO', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (524, 1, 'DE TOUR VILLAGE', 'DE TOUR VILLAGE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (525, 1, 'DE VALLS BLUFF', 'DE VALLS BLUFF', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (526, 1, 'VALLS BLUFF', 'DE VALLS BLUFF', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (527, 1, 'DE WITT', 'DE WITT', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (528, 1, 'DE YOUNG', 'DE YOUNG', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (529, 1, 'DU BOIS', 'DU BOIS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (530, 1, 'DU PONT', 'DU PONT', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (531, 1, 'DU QUOIN', 'DU QUOIN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (532, 1, 'E MC KEESPORT', 'EAST MC KEESPORT', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (533, 1, 'E MCKEESPORT', 'EAST MC KEESPORT', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (534, 1, 'EAST MC KEESPORT', 'EAST MC KEESPORT', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (535, 1, 'EAST MCKEESPORT', 'EAST MC KEESPORT', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (536, 1, 'EL CAJON', 'EL CAJON', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (537, 1, 'EL CAMPO', 'EL CAMPO', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (538, 1, 'EL CENTRO', 'EL CENTRO', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (539, 1, 'EL CERRITO', 'EL CERRITO', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (540, 1, 'EL DORADO', 'EL DORADO', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (541, 1, 'EL DORADO HILLS', 'EL DORADO HILLS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (542, 1, 'EL DORADO SPRINGS', 'EL DORADO SPRINGS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (543, 1, 'EL MIRAGE', 'EL MIRAGE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (544, 1, 'EL MONTE', 'EL MONTE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (545, 1, 'EL NIDO', 'EL NIDO', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (546, 1, 'EL PASO', 'EL PASO', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (547, 1, 'EL PRADO', 'EL PRADO', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (548, 1, 'EL RENO', 'EL RENO', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (549, 1, 'EL RITO', 'EL RITO', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (550, 1, 'EL SEGUNDO', 'EL SEGUNDO', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (551, 1, 'EL SOBRANTE', 'EL SOBRANTE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (552, 1, 'FALLS OF ROUGH', 'FALLS OF ROUGH', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (553, 1, 'FOND DU LAC', 'FOND DU LAC', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (554, 1, 'FORKS OF SALMON', 'FORKS OF SALMON', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (555, 1, 'FORT MC COY', 'FORT MC COY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (556, 1, 'FORT MCCOY', 'FORT MC COY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (557, 1, 'FORT MC KAVETT', 'FORT MC KAVETT', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (558, 1, 'FORT MCKAVETT', 'FORT MC KAVETT', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (559, 1, 'FT MITCHELL', 'FORT MITCHELL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (560, 1, 'FORT MITCHELL', 'FORT MITCHELL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (561, 1, 'FT MYER', 'FORT MYER', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (562, 1, 'FORT MYER', 'FORT MYER', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (563, 1, 'FT WARREN AFB', 'FORT WARREN AFB', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (564, 1, 'FORT WARREN AFB', 'FORT WARREN AFB', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (565, 1, 'HASTINGS ON HUDSON', 'HASTINGS ON HUDSON', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (566, 1, 'HAVRE DE GRACE', 'HAVRE DE GRACE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (567, 1, 'HI HAT', 'HI HAT', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (568, 1, 'HO HO KUS', 'HO HO KUS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (569, 1, 'HOWEY IN THE HILLS', 'HOWEY IN THE HILLS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (570, 1, 'HOWEY IN HILLS', 'HOWEY IN THE HILLS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (571, 1, 'ISLE LA MOTTE', 'ISLE LA MOTTE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (572, 1, 'ISLE OF PALMS', 'ISLE OF PALMS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (573, 1, 'ISLE OF SPRINGS', 'ISLE OF SPRINGS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (574, 1, 'JAY EM', 'JAY EM', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (575, 1, 'KING OF PRUSSIA', 'KING OF PRUSSIA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (576, 1, 'LA BARGE', 'LA BARGE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (577, 1, 'LA BELLE', 'LA BELLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (578, 1, 'LA CANADA FLINTRIDGE', 'LA CANADA FLINTRIDGE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (579, 1, 'LA CENTER', 'LA CENTER', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (580, 1, 'LA CONNER', 'LA CONNER', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (581, 1, 'LA COSTE', 'LA COSTE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (582, 1, 'LA CRESCENT', 'LA CRESCENT', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (583, 1, 'LA CRESCENTA', 'LA CRESCENTA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (584, 1, 'LA CROSSE', 'LA CROSSE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (585, 1, 'LA FARGE', 'LA FARGE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (586, 1, 'LA FARGEVILLE', 'LA FARGEVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (587, 1, 'LA FAYETTE', 'LA FAYETTE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (588, 1, 'LA FERIA', 'LA FERIA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (589, 1, 'LA FOLLETTE', 'LA FOLLETTE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (590, 1, 'LA FONTAINE', 'LA FONTAINE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (591, 1, 'LA GRANDE', 'LA GRANDE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (592, 1, 'LA GRANGE', 'LA GRANGE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (593, 1, 'LA GRANGE PARK', 'LA GRANGE PARK', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (594, 1, 'LA HABRA', 'LA HABRA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (595, 1, 'LA HARPE', 'LA HARPE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (596, 1, 'LA HONDA', 'LA HONDA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (597, 1, 'LA JARA', 'LA JARA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (598, 1, 'LA JOLLA', 'LA JOLLA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (599, 1, 'LA JOSE', 'LA JOSE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (600, 1, 'LA JOYA', 'LA JOYA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (601, 1, 'LA JUNTA', 'LA JUNTA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (602, 1, 'LA LOMA', 'LA LOMA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (603, 1, 'LA LUZ', 'LA LUZ', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (604, 1, 'LA MADERA', 'LA MADERA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (605, 1, 'LA MARQUE', 'LA MARQUE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (606, 1, 'LA MESA', 'LA MESA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (607, 1, 'LA MIRADA', 'LA MIRADA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (608, 1, 'LA MOILLE', 'LA MOILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (609, 1, 'LA MONTE', 'LA MONTE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (610, 1, 'LA MOTTE', 'LA MOTTE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (611, 1, 'LA PALMA', 'LA PALMA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (612, 1, 'LA PINE', 'LA PINE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (613, 1, 'LA PLACE', 'LA PLACE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (614, 1, 'LA PLATA', 'LA PLATA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (615, 1, 'LA PORTE', 'LA PORTE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (616, 1, 'LA PORTE CITY', 'LA PORTE CITY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (617, 1, 'LA PRAIRIE', 'LA PRAIRIE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (618, 1, 'LA PUENTE', 'LA PUENTE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (619, 1, 'LA QUINTA', 'LA QUINTA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (620, 1, 'LA RUE', 'LA RUE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (621, 1, 'LA RUSSELL', 'LA RUSSELL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (622, 1, 'LA SALLE', 'LA SALLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (623, 1, 'LA VALLE', 'LA VALLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (624, 1, 'LA VERGNE', 'LA VERGNE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (625, 1, 'LA VERKIN', 'LA VERKIN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (626, 1, 'LA VERNE', 'LA VERNE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (627, 1, 'LA VERNIA', 'LA VERNIA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (628, 1, 'LA VETA', 'LA VETA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (629, 1, 'LA VISTA', 'LA VISTA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (630, 1, 'LAC DU FLAMBEAU', 'LAC DU FLAMBEAU', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (631, 1, 'LAKE IN THE HILLS', 'LAKE IN THE HILLS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (632, 1, 'LAKE IN HILLS', 'LAKE IN THE HILLS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (633, 1, 'LE CENTER', 'LE CENTER', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (634, 1, 'LE CLAIRE', 'LE CLAIRE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (635, 1, 'LE GRAND', 'LE GRAND', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (636, 1, 'LE MARS', 'LE MARS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (637, 1, 'LE RAYSVILLE', 'LE RAYSVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (638, 1, 'LE ROY', 'LE ROY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (639, 1, 'LE SUEUR', 'LE SUEUR', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (640, 1, 'LE VERNE', 'LU VERNE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (641, 1, 'LU VERNE', 'LU VERNE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (642, 1, 'MARINE ON SAINT CROIX', 'MARINE ON SAINT CROIX', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (643, 1, 'MC ADENVILLE', 'MC ADENVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (644, 1, 'MCADENVILLE', 'MC ADENVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (645, 1, 'MC ALISTER', 'MC ALISTER', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (646, 1, 'MCALISTER', 'MC ALISTER', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (647, 1, 'MC ALISTERVILLE', 'MC ALISTERVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (648, 1, 'MCALISTERVILLE', 'MC ALISTERVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (649, 1, 'MC ALPIN', 'MC ALPIN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (650, 1, 'MCALPIN', 'MC ALPIN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (651, 1, 'MC ANDREWS', 'MC ANDREWS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (652, 1, 'MCANDREWS', 'MC ANDREWS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (653, 1, 'MC ARTHUR', 'MC ARTHUR', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (654, 1, 'MCARTHUR', 'MC ARTHUR', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (655, 1, 'MC BAIN', 'MC BAIN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (656, 1, 'MCBAIN', 'MC BAIN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (657, 1, 'MC BEE', 'MC BEE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (658, 1, 'MCBEE', 'MC BEE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (659, 1, 'MC CALL CREEK', 'MC CALL CREEK', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (660, 1, 'MCCALL CREEK', 'MC CALL CREEK', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (661, 1, 'MC CALLA', 'MC CALLA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (662, 1, 'MCCALLA', 'MC CALLA', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (663, 1, 'MC CALLSBURG', 'MC CALLSBURG', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (664, 1, 'MCCALLSBURG', 'MC CALLSBURG', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (665, 1, 'MC CAMEY', 'MC CAMEY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (666, 1, 'MCCAMEY', 'MC CAMEY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (667, 1, 'MC CARLEY', 'MC CARLEY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (668, 1, 'MCCARLEY', 'MC CARLEY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (669, 1, 'MC CARR', 'MC CARR', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (670, 1, 'MCCARR', 'MC CARR', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (671, 1, 'MC CASKILL', 'MC CASKILL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (672, 1, 'MCCASKILL', 'MC CASKILL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (673, 1, 'MC CAULLEY', 'MC CAULLEY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (674, 1, 'MCCAULLEY', 'MC CAULLEY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (675, 1, 'MC CAYSVILLE', 'MC CAYSVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (676, 1, 'MCCAYSVILLE', 'MC CAYSVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (677, 1, 'MC CLAVE', 'MC CLAVE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (678, 1, 'MCCLAVE', 'MC CLAVE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (679, 1, 'MC CLELLAND', 'MC CLELLAND', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (680, 1, 'MCCLELLAND', 'MC CLELLAND', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (681, 1, 'MC CLELLANDTOWN', 'MC CLELLANDTOWN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (682, 1, 'MCCLELLANDTOWN', 'MC CLELLANDTOWN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (683, 1, 'MC CLELLANVILLE', 'MC CLELLANVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (684, 1, 'MCCLELLANVILLE', 'MC CLELLANVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (685, 1, 'MC CLURE', 'MC CLURE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (686, 1, 'MCCLURE', 'MC CLURE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (687, 1, 'MC CLURG', 'MC CLURG', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (688, 1, 'MCCLURG', 'MC CLURG', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (689, 1, 'MC COLL', 'MC COLL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (690, 1, 'MCCOLL', 'MC COLL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (691, 1, 'MC COMB', 'MC COMB', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (692, 1, 'MCCOMB', 'MC COMB', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (693, 1, 'MC CONNELL', 'MC CONNELL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (694, 1, 'MCCONNELL', 'MC CONNELL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (695, 1, 'MC CONNELLS', 'MC CONNELLS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (696, 1, 'MCCONNELLS', 'MC CONNELLS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (697, 1, 'MC CONNELLSBURG', 'MC CONNELLSBURG', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (698, 1, 'MCCONNELLSBURG', 'MC CONNELLSBURG', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (699, 1, 'MC COOK', 'MC COOK', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (700, 1, 'MCCOOK', 'MC COOK', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (701, 1, 'MC COOL', 'MC COOL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (702, 1, 'MCCOOL', 'MC COOL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (703, 1, 'MC COOL JUNCTION', 'MC COOL JUNCTION', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (704, 1, 'MCCOOL JUNCTION', 'MC COOL JUNCTION', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (705, 1, 'MC CORDSVILLE', 'MC CORDSVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (706, 1, 'MCCORDSVILLE', 'MC CORDSVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (707, 1, 'MC CORMICK', 'MC CORMICK', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (708, 1, 'MCCORMICK', 'MC CORMICK', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (709, 1, 'MC COY', 'MC COY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (710, 1, 'MCCOY', 'MC COY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (711, 1, 'MC CRACKEN', 'MC CRACKEN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (712, 1, 'MCCRACKEN', 'MC CRACKEN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (713, 1, 'MC CRORY', 'MC CRORY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (714, 1, 'MCCRORY', 'MC CRORY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (715, 1, 'MC CUNE', 'MC CUNE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (716, 1, 'MCCUNE', 'MC CUNE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (717, 1, 'MC CUTCHENVILLE', 'MC CUTCHENVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (718, 1, 'MCCUTCHENVILLE', 'MC CUTCHENVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (719, 1, 'MC DADE', 'MC DADE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (720, 1, 'MCDADE', 'MC DADE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (721, 1, 'MC DANIELS', 'MC DANIELS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (722, 1, 'MCDANIELS', 'MC DANIELS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (723, 1, 'MC DAVID', 'MC DAVID', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (724, 1, 'MCDAVID', 'MC DAVID', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (725, 1, 'MC DERMOTT', 'MC DERMOTT', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (726, 1, 'MCDERMOTT', 'MC DERMOTT', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (727, 1, 'MC DONALD', 'MC DONALD', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (728, 1, 'MCDONALD', 'MC DONALD', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (729, 1, 'MC DONOUGH', 'MC DONOUGH', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (730, 1, 'MCDONOUGH', 'MC DONOUGH', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (731, 1, 'MC DOWELL', 'MC DOWELL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (732, 1, 'MCDOWELL', 'MC DOWELL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (733, 1, 'MC EWEN', 'MC EWEN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (734, 1, 'MCEWEN', 'MC EWEN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (735, 1, 'MC FALL', 'MC FALL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (736, 1, 'MCFALL', 'MC FALL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (737, 1, 'MC FARLAND', 'MC FARLAND', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (738, 1, 'MCFARLAND', 'MC FARLAND', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (739, 1, 'MC GAHEYSVILLE', 'MC GAHEYSVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (740, 1, 'MCGAHEYSVILLE', 'MC GAHEYSVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (741, 1, 'MC GEE', 'MC GEE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (742, 1, 'MCGEE', 'MC GEE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (743, 1, 'MC GEHEE', 'MC GEHEE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (744, 1, 'MCGEHEE', 'MC GEHEE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (745, 1, 'MC GRADY', 'MC GRADY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (746, 1, 'MCGRADY', 'MC GRADY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (747, 1, 'MC GRATH', 'MC GRATH', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (748, 1, 'MCGRATH', 'MC GRATH', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (749, 1, 'MC GRAW', 'MC GRAW', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (750, 1, 'MCGRAW', 'MC GRAW', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (751, 1, 'MC GREGOR', 'MC GREGOR', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (752, 1, 'MCGREGOR', 'MC GREGOR', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (753, 1, 'MC HENRY', 'MC HENRY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (754, 1, 'MCHENRY', 'MC HENRY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (755, 1, 'MC INTIRE', 'MC INTIRE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (756, 1, 'MCINTIRE', 'MC INTIRE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (757, 1, 'MC INTOSH', 'MC INTOSH', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (758, 1, 'MCINTOSH', 'MC INTOSH', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (759, 1, 'MC INTYRE', 'MC INTYRE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (760, 1, 'MCINTYRE', 'MC INTYRE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (761, 1, 'MC KEAN', 'MC KEAN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (762, 1, 'MCKEAN', 'MC KEAN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (763, 1, 'MC KEE', 'MC KEE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (764, 1, 'MCKEE', 'MC KEE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (765, 1, 'MC KEES ROCKS', 'MC KEES ROCKS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (766, 1, 'MCKEES ROCKS', 'MC KEES ROCKS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (767, 1, 'MC KENNEY', 'MC KENNEY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (768, 1, 'MCKENNEY', 'MC KENNEY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (769, 1, 'MC KENZIE', 'MC KENZIE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (770, 1, 'MCKENZIE', 'MC KENZIE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (771, 1, 'MC KITTRICK', 'MC KITTRICK', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (772, 1, 'MCKITTRICK', 'MC KITTRICK', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (773, 1, 'MC LAIN', 'MC LAIN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (774, 1, 'MCLAIN', 'MC LAIN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (775, 1, 'MC LAUGHLIN', 'MC LAUGHLIN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (776, 1, 'MCLAUGHLIN', 'MC LAUGHLIN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (777, 1, 'MC LEAN', 'MC LEAN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (778, 1, 'MCLEAN', 'MC LEAN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (779, 1, 'MC LEANSBORO', 'MC LEANSBORO', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (780, 1, 'MCLEANSBORO', 'MC LEANSBORO', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (781, 1, 'MC LEANSVILLE', 'MC LEANSVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (782, 1, 'MCLEANSVILLE', 'MC LEANSVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (783, 1, 'MC LEOD', 'MC LEOD', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (784, 1, 'MCLEOD', 'MC LEOD', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (785, 1, 'MC LOUTH', 'MC LOUTH', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (786, 1, 'MCLOUTH', 'MC LOUTH', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (787, 1, 'MC MILLAN', 'MC MILLAN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (788, 1, 'MCMILLAN', 'MC MILLAN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (789, 1, 'MC MINNVILLE', 'MC MINNVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (790, 1, 'MCMINNVILLE', 'MC MINNVILLE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (791, 1, 'MC NABB', 'MC NABB', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (792, 1, 'MCNABB', 'MC NABB', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (793, 1, 'MC NEAL', 'MC NEAL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (794, 1, 'MCNEAL', 'MC NEAL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (795, 1, 'MC NEIL', 'MC NEIL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (796, 1, 'MCNEIL', 'MC NEIL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (797, 1, 'MC QUEENEY', 'MC QUEENEY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (798, 1, 'MCQUEENEY', 'MC QUEENEY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (799, 1, 'MC RAE', 'MC RAE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (800, 1, 'MCRAE', 'MC RAE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (801, 1, 'MC ROBERTS', 'MC ROBERTS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (802, 1, 'MCROBERTS', 'MC ROBERTS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (803, 1, 'MC SHERRYSTOWN', 'MC SHERRYSTOWN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (804, 1, 'MCSHERRYSTOWN', 'MC SHERRYSTOWN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (805, 1, 'MC VEYTOWN', 'MC VEYTOWN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (806, 1, 'MCVEYTOWN', 'MC VEYTOWN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (807, 1, 'MEADOWS OF DAN', 'MEADOWS OF DAN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (808, 1, 'MI WUK VILLAGE', 'MI WUK VILLAGE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (809, 1, 'MOUTH OF WILSON', 'MOUTH OF WILSON', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (810, 1, 'MT ZION', 'MOUNT ZION', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (811, 1, 'MOUNT ZION', 'MOUNT ZION', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (812, 1, 'PE ELL', 'PE ELL', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (813, 1, 'POINT OF ROCKS', 'POINT OF ROCKS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (814, 1, 'PONCE DE LEON', 'PONCE DE LEON', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (815, 1, 'PRAIRIE DU CHIEN', 'PRAIRIE DU CHIEN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (816, 1, 'PRAIRIE DU ROCHER', 'PRAIRIE DU ROCHER', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (817, 1, 'PRAIRIE DU SAC', 'PRAIRIE DU SAC', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (818, 1, 'RANCHO SANTA FE', 'RANCHO SANTA FE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (819, 1, 'RANCHOS DE TAOS', 'RANCHOS DE TAOS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (820, 1, 'SAINT JO', 'SAINT JO', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (821, 1, 'SANTA FE', 'SANTA FE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (822, 1, 'SANTA FE SPRINGS', 'SANTA FE SPRINGS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (823, 1, 'S EL MONTE', 'SOUTH EL MONTE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (824, 1, 'SOUTH EL MONTE', 'SOUTH EL MONTE', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (825, 1, 'SAINT COLUMBANS', 'SAINT COLUMBANS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (826, 1, 'ST COLUMBANS', 'SAINT COLUMBANS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (827, 1, 'SAINT JOHN', 'SAINT JOHN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (828, 1, 'ST JOHN', 'SAINT JOHN', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (829, 1, 'SAINT THOMAS', 'SAINT THOMAS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (830, 1, 'ST THOMAS', 'SAINT THOMAS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (831, 1, 'TOWNSHIP OF WASHINGTON', 'TOWNSHIP OF WASHINGTON', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (832, 1, 'TRUTH OR CONSEQUENCES', 'TRUTH OR CONSEQUENCES', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (833, 1, 'TY TY', 'TY TY', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (834, 1, 'VILLAGE OF NAGOG WOODS', 'VILLAGE OF NAGOG WOODS', 10, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (7, 1, 'AK', 'AK', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (9, 3, 'AK', 'AK', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (10, 1, 'AL', 'AL', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (12, 3, 'AL', 'AL', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (13, 1, 'ALA', 'AL', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (15, 3, 'ALA', 'AL', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (16, 1, 'ALABAMA', 'AL', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (18, 1, 'ALASKA', 'AK', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (22, 1, 'AR', 'AR', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (24, 3, 'AR', 'AR', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (25, 1, 'ARIZ', 'AZ', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (27, 3, 'ARIZ', 'AZ', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (28, 1, 'ARIZONA', 'AZ', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (30, 1, 'ARK', 'AR', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (32, 3, 'ARK', 'AR', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (33, 1, 'ARKANSAS', 'AR', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (35, 1, 'AZ', 'AZ', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (37, 3, 'AZ', 'AZ', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (46, 1, 'CA', 'CA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (48, 3, 'CA', 'CA', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (51, 1, 'CALIF', 'CA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (53, 3, 'CALIF', 'CA', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (54, 1, 'CALIFORNIA', 'CA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (58, 1, 'CO', 'CO', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (60, 3, 'CO', 'CO', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (63, 1, 'COLORADO', 'CO', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (65, 1, 'CONN', 'CT', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (67, 3, 'CONN', 'CT', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (68, 1, 'CONNECTICUT', 'CT', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (70, 1, 'CT', 'CT', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (72, 3, 'CT', 'CT', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (73, 1, 'DC', 'DC', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (75, 3, 'DC', 'DC', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (76, 1, 'DE', 'DE', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (78, 1, 'DEL', 'DE', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (80, 3, 'DEL', 'DE', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (81, 1, 'DELAWARE', 'DE', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (83, 1, 'DC', 'DC', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (86, 1, 'FL', 'FL', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (88, 3, 'FL', 'FL', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (89, 1, 'FLA', 'FL', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (91, 3, 'FLA', 'FL', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (92, 1, 'FLORIDA', 'FL', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (95, 1, 'GA', 'GA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (97, 3, 'GA', 'GA', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (98, 1, 'GEORGIA', 'GA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (100, 1, 'HAWAII', 'HI', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (102, 1, 'HI', 'HI', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (104, 3, 'HI', 'HI', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (105, 1, 'IA', 'IA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (107, 3, 'IA', 'IA', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (108, 1, 'ID', 'ID', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (110, 3, 'ID', 'ID', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (111, 1, 'IDAHO', 'ID', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (113, 1, 'IL', 'IL', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (115, 3, 'IL', 'IL', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (118, 1, 'ILL', 'IL', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (120, 3, 'ILL', 'IL', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (121, 1, 'ILLINOIS', 'IL', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (123, 1, 'IN', 'IN', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (125, 3, 'IN', 'IN', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (126, 1, 'IND', 'IN', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (128, 2, 'IND', 'IN', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (129, 1, 'INDIANA', 'IN', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (131, 1, 'IOWA', 'IA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (133, 1, 'KANSAS', 'KS', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (135, 1, 'KENT', 'KY', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (137, 3, 'KENT', 'KY', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (138, 1, 'KENTUCKY', 'KY', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (140, 1, 'KS', 'KS', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (142, 3, 'KS', 'KS', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (143, 1, 'KY', 'KY', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (145, 3, 'KY', 'KY', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (146, 1, 'LA', 'LA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (148, 3, 'LA', 'LA', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (151, 1, 'LOUISIANA', 'LA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (153, 1, 'MA', 'MA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (155, 3, 'MA', 'MA', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (157, 1, 'MAINE', 'ME', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (161, 1, 'MARYLAND', 'MD', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (163, 1, 'MASS', 'MA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (165, 3, 'MASS', 'MA', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (166, 1, 'MASSACHUSETTS', 'MA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (171, 1, 'MD', 'MD', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (173, 3, 'MD', 'MD', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (174, 1, 'ME', 'ME', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (176, 3, 'ME', 'ME', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (177, 1, 'MI', 'MI', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (179, 3, 'MI', 'MI', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (180, 1, 'MICH', 'MI', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (182, 3, 'MICH', 'MI', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (183, 1, 'MICHIGAN', 'MI', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (185, 1, 'MINN', 'MN', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (187, 3, 'MINN', 'MN', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (188, 1, 'MINNESOTA', 'MN', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (190, 1, 'MISSISSIPPI', 'MS', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (192, 1, 'MISSOURI', 'MO', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (194, 1, 'MN', 'MN', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (196, 3, 'MN', 'MN', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (197, 1, 'MO', 'MO', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (199, 3, 'MO', 'MO', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (200, 1, 'MONT', 'MT', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (202, 3, 'MONT', 'MT', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (203, 1, 'MONTANA', 'MT', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (205, 1, 'MT', 'MT', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (207, 3, 'MT', 'MT', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (208, 1, 'MS', 'MS', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (210, 3, 'MS', 'MS', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (211, 1, 'N CAROLINA', 'NC', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (213, 1, 'N DAKOTA', 'ND', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (218, 1, 'NC', 'NC', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (220, 3, 'NC', 'NC', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (221, 1, 'ND', 'ND', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (223, 3, 'ND', 'ND', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (224, 1, 'NE', 'NE', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (226, 3, 'NE', 'NE', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (227, 1, 'NEB', 'NE', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (229, 3, 'NEB', 'NE', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (230, 1, 'NEBRASKA', 'NE', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (232, 1, 'NEV', 'NV', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (234, 3, 'NEV', 'NV', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (235, 1, 'NEVADA', 'NV', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (239, 1, 'NEW HAMPSHIRE', 'NH', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (241, 1, 'NEW JERSEY', 'NJ', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (243, 1, 'NEW MEXICO', 'NM', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (245, 1, 'NEW YORK', 'NY', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (252, 1, 'NH', 'NH', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (254, 3, 'NH', 'NH', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (255, 1, 'NJ', 'NJ', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (257, 3, 'NJ', 'NJ', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (261, 1, 'NM', 'NM', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (263, 3, 'NM', 'NM', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (264, 1, 'NORTH CAROLINA', 'NC', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (266, 1, 'NORTH DAKOTA', 'ND', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (288, 1, 'NV', 'NV', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (290, 3, 'NV', 'NV', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (291, 1, 'NY', 'NY', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (293, 3, 'NY', 'NY', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (294, 1, 'OH', 'OH', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (296, 3, 'OH', 'OH', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (297, 1, 'OHIO', 'OH', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (299, 1, 'OK', 'OK', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (301, 3, 'OK', 'OK', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (302, 1, 'OKLA', 'OK', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (304, 3, 'OKLA', 'OK', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (305, 1, 'OKLAHOMA', 'OK', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (315, 1, 'OR', 'OR', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (317, 3, 'OR', 'OR', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (318, 1, 'ORE', 'OR', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (320, 3, 'ORE', 'OR', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (321, 1, 'OREGON', 'OR', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (323, 1, 'PA', 'PA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (325, 3, 'PA', 'PA', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (332, 1, 'PENN', 'PA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (334, 3, 'PENN', 'PA', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (335, 1, 'PENNA', 'PA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (337, 3, 'PENNA', 'PA', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (338, 1, 'PENNSYLVANIA', 'PA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (343, 1, 'PR', 'PR', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (345, 3, 'PR', 'PR', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (348, 1, 'PUERTO RICO', 'PR', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (355, 1, 'RHODE ISLAND', 'RI', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (357, 1, 'RI', 'RI', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (359, 3, 'RI', 'RI', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (360, 1, 'S CAROLINA', 'SC', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (362, 1, 'S DAKOTA', 'SD', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (368, 1, 'SC', 'SC', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (370, 3, 'SC', 'SC', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (371, 1, 'SD', 'SD', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (373, 3, 'SD', 'SD', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (377, 1, 'SOUTH CAROLINA', 'SC', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (379, 1, 'SOUTH DAKOTA', 'SD', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (381, 1, 'TENN', 'TN', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (383, 3, 'TENN', 'TN', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (384, 1, 'TENNESSEE', 'TN', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (390, 1, 'TEX', 'TX', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (392, 3, 'TEX', 'TX', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (393, 1, 'TEXAS', 'TX', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (395, 1, 'TN', 'TN', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (397, 3, 'TN', 'TN', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (398, 1, 'TX', 'TX', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (400, 3, 'TX', 'TX', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (408, 1, 'UT', 'UT', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (410, 3, 'UT', 'UT', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (411, 1, 'UTAH', 'UT', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (413, 1, 'VA', 'VA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (415, 3, 'VA', 'VA', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (416, 1, 'VERMONT', 'VT', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (418, 1, 'VIRGINIA', 'VA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (420, 1, 'VT', 'VT', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (422, 3, 'VT', 'VT', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (423, 1, 'W VIRGINIA', 'WV', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (425, 1, 'WA', 'WA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (427, 3, 'WA', 'WA', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (428, 1, 'WASH', 'WA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (430, 3, 'WASH', 'WA', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (431, 1, 'WASHINGTON', 'WA', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (433, 1, 'WEST VIRGINIA', 'WV', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (435, 1, 'WI', 'WI', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (437, 3, 'WI', 'WI', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (438, 1, 'WISC', 'WI', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (440, 3, 'WISC', 'WI', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (441, 1, 'WISCONSIN', 'WI', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (443, 1, 'WV', 'WV', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (445, 3, 'WV', 'WV', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (446, 1, 'WY', 'WY', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (448, 3, 'WY', 'WY', 6, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (449, 1, 'WYOMING', 'WY', 11, false);
INSERT INTO pagc_gaz (id, seq, word, stdword, token, is_custom) VALUES (835, 1, 'ST LOUIS', 'SAINT LOUIS', 7, false);

SELECT pg_catalog.setval('pagc_gaz_id_seq', (SELECT greatest((SELECT MAX(id) FROM pagc_gaz),50000)), true);

-- start pagc_lex --
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2934, 1, 'BAY STATE', 'BAY STATE', 5, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2389, 2, 'STAT', 'STA', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2382, 2, 'STA', 'STA', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2403, 2, 'STATION', 'STA', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2407, 2, 'STATN', 'STA', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2394, 1, 'STATE HIGHWAY', 'STATE HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2368, 1, 'ST HIGHWAY', 'STATE HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2393, 1, 'STATE HI', 'STATE HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2369, 1, 'ST HWY', 'STATE HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2414, 1, 'STHWY', 'STATE HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2415, 1, 'STHY', 'STATE HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2367, 1, 'ST HI', 'STATE HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2413, 1, 'STHW', 'STATE HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2370, 1, 'ST HY', 'STATE HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2396, 1, 'STATE HY', 'STATE HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2373, 1, 'ST RD', 'STATE RD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (212, 2, 'AND', 'AND', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2395, 1, 'STATE HWY', 'STATE HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (413, 2, 'BYP', 'BYP', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2397, 1, 'STATE RD', 'STATE RD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2374, 1, 'ST ROAD', 'STATE RD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1561, 2, 'MANORS', 'MANOR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2398, 1, 'STATE ROAD', 'STATE RD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2377, 1, 'ST RT', 'STATE RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1937, 1, 'PR ROUTE', 'STATE RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2399, 1, 'STATE ROUTE', 'STATE RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2375, 1, 'ST ROUTE', 'STATE RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2401, 1, 'STATE RTE', 'STATE RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2400, 1, 'STATE RT', 'STATE RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2379, 1, 'ST RTE', 'STATE RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2493, 1, 'TERR', 'TER', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2488, 1, 'TER', 'TER', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2555, 1, 'THRUWAY', 'TRWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2556, 1, 'THWY', 'TRWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2554, 1, 'THROUGHWAY', 'TRWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2599, 2, 'TPK', 'TPKE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2683, 2, 'TURNPK', 'TPKE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2681, 2, 'TURNPIKE', 'TPKE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2601, 2, 'TPKE', 'TPKE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2679, 2, 'TURN', 'TPKE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2496, 1, 'TFWY', 'TRFY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2616, 1, 'TRAIL', 'TRL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2631, 1, 'TRAILS', 'TRL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2559, 1, 'TL', 'TRL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2674, 1, 'TUNEL', 'TUNL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2675, 1, 'TUNL', 'TUNL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2673, 1, 'TUN', 'TUNL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2676, 1, 'TUNNEL', 'TUNL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2569, 1, 'TNPKE', 'TPKE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2568, 1, 'TNPK', 'TPKE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2682, 1, 'TURNPK', 'TPKE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2680, 1, 'TURNPIKE', 'TPKE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2678, 1, 'TURN', 'TPKE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2665, 1, 'TRNPK', 'TPKE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2600, 1, 'TPKE', 'TPKE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2598, 1, 'TPK', 'TPKE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2768, 1, 'U S HY', 'US HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2782, 1, 'UNITED STATES HWY', 'US HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2764, 1, 'U S HGWY', 'US HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2765, 1, 'U S HIGHWAY', 'US HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2781, 1, 'UNITED STATES HIGHWAY', 'US HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2807, 1, 'US HGWY', 'US HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2808, 1, 'US HIGHWAY', 'US HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2809, 1, 'US HIWAY', 'US HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2810, 1, 'US HWY', 'US HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2811, 1, 'US HY', 'US HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2819, 1, 'USHW', 'US HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2820, 1, 'USHWY', 'US HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2821, 1, 'USHY', 'US HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2824, 1, 'USRT', 'US RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2825, 1, 'USRTE', 'US RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2816, 1, 'US RTE', 'US RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2814, 1, 'US ROUTE', 'US RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2770, 1, 'U S RT', 'US RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2805, 1, 'US', 'US RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2815, 1, 'US RT', 'US RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2763, 1, 'U S', 'US RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2769, 1, 'U S ROUTE', 'US RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2771, 1, 'U S RTE', 'US RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2823, 1, 'USROUTE', 'US RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2878, 2, 'VW', 'VW', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2869, 1, 'VLGE', 'VLG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2866, 1, 'VLG', 'VLG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2865, 2, 'VL', 'VLG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2855, 1, 'VILLIAGE', 'VLG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2854, 1, 'VILLGE', 'VLG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2851, 1, 'VILLG', 'VLG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2846, 1, 'VILLAGE', 'VLG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2843, 1, 'VILLAG', 'VLG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2861, 2, 'VISTA', 'VIS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2859, 2, 'VIS', 'VIS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2856, 2, 'VILLIAGE', 'VLG', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2838, 2, 'VILL', 'VLG', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2847, 2, 'VILLAGE', 'VLG', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2844, 2, 'VILLAG', 'VLG', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2870, 2, 'VLGE', 'VLG', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2852, 2, 'VILLG', 'VLG', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2867, 2, 'VLG', 'VLG', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2881, 1, 'WALK', 'WALK', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2903, 1, 'WK', 'WALK', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2884, 1, 'WALL', 'WALL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2914, 1, 'WY', 'WAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2915, 4, 'WY', 'WAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2888, 1, 'WAY', 'WAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (691, 2, 'CROSSING', 'XING', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2918, 2, 'XING', 'XING', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (692, 1, 'CROSSINGS', 'XING', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (701, 1, 'CRSGS', 'XING', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (704, 2, 'CRSSNG', 'XING', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (700, 2, 'CRSG', 'XING', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (688, 1, 'CROSS ROAD', 'XRD', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1762, 1, 'NORTH', 'N', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1764, 1, 'NORTH EAST', 'NE', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1766, 1, 'NORTH WEST', 'NW', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1769, 1, 'NORTHEAST', 'NE', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1771, 1, 'NTH', 'N', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1774, 1, 'NW', 'NW', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2931, 1, 'SERVICE DR', 'SVC DR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2932, 1, 'SERVICE DRIVE', 'SVC DR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2933, 1, 'SVC DR', 'SVC DR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2392, 2, 'STATE', 'STATE RD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (59, 1, '20MI', 'TWENTY MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (60, 1, '21ST', '21', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (61, 2, '21ST', '21ST', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (62, 1, '22ND', '22', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (63, 2, '22ND', '22ND', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (64, 1, '23 MI', 'TWENTY THREE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (65, 1, '23 MILE', 'TWENTY THREE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (66, 1, '23MI', 'TWENTY THREE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (67, 1, '23RD', '23', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (68, 2, '23RD', '23RD', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (69, 1, '2MI', 'TWO MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2767, 1, 'U S HWY', 'US HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (70, 1, '3 / 4', '3/4', 25, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (71, 1, '3 / 8', '3/8', 25, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (72, 1, '3 MI', 'THREE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (73, 1, '3 MILE', 'THREE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (75, 1, '3/8', '3/8', 25, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (76, 1, '31ST', '31', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (77, 2, '31ST', '31ST', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (78, 1, '33RD', '33', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (79, 2, '33RD', '33RD', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (80, 1, '3MI', 'THREE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (81, 1, '3RD', '3', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (82, 2, '3RD', '3RD', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (83, 1, '4 CO', 'FOUR CORNERS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (84, 1, '4 CORNERS', 'FOUR CORNERS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (85, 1, '4 FG', 'FOUR FLAGS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (86, 1, '4 FLAGS', 'FOUR FLAGS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (87, 1, '4 MI', 'FOUR MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (88, 1, '4 MILE', 'FOUR MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (89, 1, '4 SEASONS', 'FOUR SEASONS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (90, 1, '4 SN', 'FOUR SEASONS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (91, 1, '41ST', '41', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (92, 2, '41ST', '41ST', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (93, 1, '43RD', '43', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (94, 2, '43RD', '43RD', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (95, 1, '4MI', 'FOUR MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (96, 1, '4WD', 'FOUR WHEEL DRIVE TRAIL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (97, 1, '4WD TRAIL', 'FOUR WHEEL DRIVE TRAIL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (98, 1, '4WD TRL', 'FOUR WHEEL DRIVE TRAIL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (99, 1, '5 CEDARS', 'FIVE CEDARS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (100, 1, '5 CO', 'FIVE CORNERS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (101, 1, '5 CORNERS', 'FIVE CORNERS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (102, 1, '5 MI', 'FIVE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (103, 1, '5 MILE', 'FIVE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (104, 1, '5 POINTS', 'FIVE POINTS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (105, 1, '5 PT', 'FIVE POINTS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (106, 1, '5 TO', 'FIVE TOWN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (107, 1, '51ST', '51', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (108, 2, '51ST', '51', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (109, 1, '53RD', '53', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (110, 2, '53RD', '53RD', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (111, 1, '5MI', 'FIVE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (112, 1, '6 FG', 'SIX FLAGS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (113, 1, '6 FLAGS', 'SIX FLAGS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (114, 1, '6 MI', 'SIX MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (115, 1, '6 MILE', 'SIX MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (116, 1, '61ST', '61', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (117, 2, '61ST', '61ST', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (118, 1, '63RD', '63', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (119, 2, '63RD', '63RD', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (120, 1, '6MI', 'SIX MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (121, 1, '7 CO', 'SEVEN CORNERS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (122, 2, '7 CO', 'SEVEN CORNERS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (123, 1, '7 CORNERS', 'SEVEN CORNERS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (124, 2, '7 CORNERS', 'SEVEN CORNERS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (125, 1, '7 MI', 'SEVEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (126, 1, '7 MILE', 'SEVEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (127, 1, '71ST', '71', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (128, 2, '71ST', '71ST', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (129, 1, '73RD', '73', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (130, 2, '73RD', '73RD', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (131, 1, '7MI', 'SEVEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (132, 1, '8 MI', 'EIGHT MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (133, 1, '8 MILE', 'EIGHT MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (134, 1, '81ST', '81', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (135, 2, '81ST', '81ST', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (136, 1, '83RD', '83', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (137, 2, '83RD', '83RD', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (138, 1, '8MI', 'EIGHT MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (139, 1, '9 MI', 'NINE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (140, 1, '9 MILE', 'NINE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (141, 1, '91ST', '91', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (142, 2, '91ST', '91ST', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (143, 1, '93RD', '93', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (144, 2, '93RD', '93RD', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (145, 1, '9MI', 'NINE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (146, 1, 'A', 'A', 18, false);
--INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (147, 2, 'A', 'A', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (148, 1, 'A F B', 'AIR FORCE BASE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (149, 2, 'A F B', 'AIR FORCE BASE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (150, 1, 'A F S', 'AIR FORCE BASE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (151, 2, 'A F S', 'AIR FORCE BASE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (152, 1, 'A LA DERECHA', 'A LA DERECHA', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (153, 4, 'AB', 'ABBEY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (154, 1, 'ABBEY', 'ABBEY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (155, 2, 'ABBEY', 'ABBEY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (156, 1, 'AC', 'ACRES', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (157, 1, 'ACAD', 'ACADEMY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (158, 1, 'ACADE', 'ACADEMIA', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (159, 1, 'ACADEMIA', 'ACADEMIA', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (160, 1, 'ACADEMY', 'ACADEMY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (161, 1, 'ACCESS', 'ACCESS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (162, 1, 'ACR', 'ACRES', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (163, 2, 'ACR', 'ACRES', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (164, 3, 'ACR', 'ACRES', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (165, 1, 'ACRES', 'ACRES', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (166, 2, 'ACRES', 'ACRES', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (74, 1, '3/4', '3/4', 25, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (167, 3, 'ACRES', 'ACRES', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (168, 1, 'ACRS', 'ACRES', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (169, 2, 'ACRS', 'ACRES', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (170, 3, 'ACRS', 'ACRES', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (171, 1, 'ACUE', 'ACUEDUCTO', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (172, 1, 'ACUED', 'ACUEDUCTO', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (173, 1, 'ACUEDUCTO', 'ACUEDUCTO', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (174, 1, 'AEROPUERTO', 'AEROPUERTO', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (175, 2, 'AEROPUERTO', 'AEROPUERTO', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (176, 1, 'AFB', 'AIR FORCE BASE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (177, 2, 'AFB', 'AIR FORCE BASE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (178, 1, 'AFLD', 'AIRPORT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (179, 1, 'AFS', 'AIR FORCE BASE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (180, 2, 'AFS', 'AIR FORCE BASE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (181, 1, 'AIR FORCE BASE', 'AIR FORCE BASE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (182, 2, 'AIR FORCE BASE', 'AIR FORCE BASE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (183, 1, 'AIR FORCE STATION', 'AIR FORCE BASE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (184, 2, 'AIR FORCE STATION', 'AIR FORCE BASE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (185, 1, 'AIRFIELD', 'AIRPORT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (186, 2, 'AIRFIELD', 'AIRPORT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (187, 1, 'AIRPARK', 'AIRPORT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (188, 2, 'AIRPARK', 'AIRPORT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (189, 1, 'AIRPORT', 'AIRPORT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (190, 2, 'AIRPORT', 'AIRPORT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (191, 1, 'AIRSTRIP', 'AIRPORT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (192, 2, 'AIRSTRIP', 'AIRPORT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (193, 1, 'AIRSTRP', 'AIRPORT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (194, 2, 'AIRSTRP', 'AIRPORT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (198, 1, 'ALC', 'ALCOVE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (199, 1, 'ALD', 'A LA DERECHA', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (202, 2, 'ALLEY', 'ALLEY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (204, 1, 'ALT', 'ALTERNATE', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (205, 1, 'ALTERNATE', 'ALTERNATE', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (206, 1, 'ALTO', 'ALTO', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (207, 2, 'ALTO', 'ALTOS', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (208, 1, 'ALTOS', 'ALTOS', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (209, 2, 'ALTOS', 'ALTOS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (213, 1, 'ANEX', 'ANNEX', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (215, 1, 'ANNEX', 'ANNEX', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (217, 1, 'ANNX', 'ANNEX', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (219, 1, 'ANX', 'ANNEX', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (221, 1, 'AP', 'APT', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (222, 1, 'APART', 'APT', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (223, 1, 'APARTEMENT', 'APT', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2938, 1, 'APARTMENT', 'APARTMENT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (224, 1, 'APARTMENT', 'APT', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (225, 1, 'APARTMENTS', 'APS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (226, 1, 'APARTADO', 'BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (227, 1, 'APO', 'APO', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (228, 1, 'APP', 'APT', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (229, 1, 'APPART', 'APT', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (230, 1, 'APPT', 'APT', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (231, 1, 'APRK', 'AIRPORT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (232, 1, 'APS', 'APS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (233, 1, 'APT', 'APT', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (234, 1, 'APT NO', 'APT', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (235, 1, 'APTMT', 'APARTMENT', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (236, 1, 'APTS', 'APARTMENTS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (237, 1, 'AR', 'ARRIERE', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (242, 1, 'ARPT', 'AIRPORT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (243, 2, 'ARPT', 'AIRPORT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (244, 1, 'ARPTO', 'AIRPORT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (245, 2, 'ARPTO', 'AIRPORT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (246, 1, 'ARRIERE', 'ARRIERE', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (247, 1, 'ARROYO', 'ARROYO', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (248, 1, 'ARRYO', 'ARROYO', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (249, 1, 'AT', 'AT', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (250, 1, 'ATPS', 'AUTOPISTA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (251, 1, 'ATPTA', 'AUTOPISTA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (252, 1, 'ATTN', 'ATTENTION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (253, 1, 'AU', 'AUTOROUTE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (254, 2, 'AU', 'AU', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (255, 1, 'AUT', 'AUTOROUTE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (256, 1, 'AUTO', 'AUTOPISTA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (257, 2, 'AUTO', 'AUTO', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (258, 1, 'AUTOPISTA', 'AUTOPISTA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (259, 1, 'AUTOROUTE', 'AUTOROUTE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (261, 2, 'AV', 'AVANT', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (262, 1, 'AVA', 'AVENIDA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (263, 1, 'AVANT', 'AVANT', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (266, 1, 'AVENIDA', 'AVENIDA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (200, 1, 'ALLEE', 'ALY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (203, 1, 'ALLY', 'ALY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (195, 1, 'AL', 'ALY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (201, 1, 'ALLEY', 'ALY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (210, 1, 'ALY', 'ALY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (238, 1, 'ARC', 'ARC', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (240, 1, 'ARCADE', 'ARC', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (260, 1, 'AV', 'AVE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (269, 1, 'AVENUES', 'AVENUES', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (270, 1, 'AVES', 'AVENUES', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (273, 1, 'AVS', 'AVENUES', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (274, 1, 'BA', 'BAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (275, 1, 'BAJO', 'BAJOS', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (276, 1, 'BAJOS', 'BAJOS', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (277, 1, 'BANK', 'BANK', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (278, 1, 'BARRIO', 'BOROUGH', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (279, 1, 'BASEMENT', 'BASEMENT', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (280, 1, 'BASIN', 'BASIN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (281, 1, 'BASN', 'BASIN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (282, 1, 'BAY', 'BAY', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (283, 2, 'BAY', 'BAY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (284, 3, 'BAY', 'BAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (285, 1, 'BAYOU', 'BAYOU', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (286, 1, 'BAZAAR', 'BAZAAR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (287, 1, 'BAZR', 'BAZAAR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (288, 1, 'BCH', 'BEACH', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (291, 1, 'BDG', 'BUILDING', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (292, 2, 'BDG', 'BUILDING', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (293, 1, 'BDNG', 'BUILDING', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (294, 2, 'BDNG', 'BUILDING', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (295, 1, 'BDWY', 'BROADWAY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (297, 1, 'BEACH', 'BEACH', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (299, 1, 'BEND', 'BEND', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (301, 1, 'BETWEEN', 'BETWEEN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (302, 1, 'BG', 'BURG', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (305, 1, 'BLD', 'BUILDING', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (306, 2, 'BLD', 'BUILDING', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (307, 1, 'BLDG', 'BUILDING', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (308, 2, 'BLDG', 'BUILDING', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (309, 1, 'BLDING', 'BUILDING', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (310, 2, 'BLDING', 'BUILDING', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (311, 1, 'BLDNG', 'BUILDING', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (312, 2, 'BLDNG', 'BUILDING', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (313, 1, 'BLF', 'BLUFF', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (315, 1, 'BLG', 'BUILDING', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (316, 2, 'BLG', 'BUILDING', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (317, 1, 'BLUF', 'BLUFF', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (318, 1, 'BLUFF', 'BLUFF', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (322, 1, 'BLVR', 'BULEVAR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (323, 1, 'BND', 'BEND', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (325, 1, 'BNK', 'BANK', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (326, 1, 'BO', 'BOROUGH', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (327, 2, 'BO', 'BOURG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (328, 1, 'BOITE', 'BOITE', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (329, 1, 'BOITE POSTALE', 'BOITE POSTALE', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (330, 1, 'BORO', 'BOROUGH', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (331, 1, 'BOROUGH', 'BOROUGH', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (333, 2, 'BOT', 'BOTTOM', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (335, 2, 'BOTTM', 'BOTTOM', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (337, 2, 'BOTTOM', 'BOTTOM', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (341, 1, 'BOURG', 'BOURG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (342, 1, 'BOX', 'BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (343, 1, 'BOX NO', 'BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (346, 3, 'BP', 'BOITE POSTALE', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (347, 1, 'BR', 'BRANCH', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (348, 1, 'BRANCH', 'BRANCH', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (349, 1, 'BRDG', 'BRIDGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (350, 1, 'BRDGE', 'BRIDGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (351, 1, 'BRDWY', 'BROADWAY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (352, 1, 'BRG', 'BRIDGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (354, 1, 'BRIDGE', 'BRIDGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (355, 1, 'BRIDGES', 'BRIDGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (356, 1, 'BRK', 'BROOK', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (357, 1, 'BROADWAY', 'BROADWAY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (358, 1, 'BROOK', 'BROOK', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (359, 1, 'BRWY', 'BROADWAY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (360, 1, 'BSMNT', 'BASEMENT', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (361, 1, 'BSMT', 'BASEMENT', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (362, 1, 'BSPK', 'BUSINESS PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (405, 1, 'BV', 'BLVD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (363, 1, 'BSRT', 'BUSINESS ROUTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (364, 1, 'BSRTE', 'BUSINESS ROUTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (365, 1, 'BST', 'BASEMENT', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (366, 1, 'BTM', 'BOTTOM', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (367, 1, 'BTWN', 'BETWEEN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (368, 1, 'BUENA VISTA', 'BUENA VISTA', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (369, 1, 'BUILD', 'BUILDING', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (370, 2, 'BUILD', 'BUILDING', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (371, 1, 'BUILDING', 'BUILDING', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (372, 2, 'BUILDING', 'BUILDING', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (373, 1, 'BUILDING NUMBER', '#', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (374, 1, 'BUILDNG', 'BUILDING', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (375, 2, 'BUILDNG', 'BUILDING', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (376, 1, 'BULDNG', 'BUILDING', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (377, 2, 'BULDNG', 'BUILDING', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (378, 1, 'BULEVAR', 'BULEVAR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (379, 1, 'BUR', 'BUREAU', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (380, 1, 'BUREAU', 'BUREAU', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (381, 2, 'BUREAU', 'BUREAU', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (382, 3, 'BUREAU', 'BUREAU', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (383, 1, 'BURG', 'BURG', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (384, 1, 'BUS', 'BUSINESS', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (385, 1, 'BUS CENTER', 'BUSINESS PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (386, 1, 'BUS CENTR', 'BUSINESS PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (387, 1, 'BUS CTR', 'BUSINESS PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (388, 1, 'BUS PARK', 'BUSINESS PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (389, 1, 'BUS PK', 'BUSINESS PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (390, 1, 'BUSCENTER', 'BUSINESS PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (391, 1, 'BUSCENTR', 'BUSINESS PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (392, 1, 'BUSCTR', 'BUSINESS PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (393, 1, 'BUSINESS', 'BUSINESS', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (394, 2, 'BUSINESS', 'BUSINESS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (395, 1, 'BUSINESS CENTER', 'BUSINESS PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (396, 1, 'BUSINESS CENTR', 'BUSINESS PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (397, 1, 'BUSINESS CTR', 'BUSINESS PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (398, 1, 'BUSINESS PARK', 'BUSINESS PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (271, 1, 'AVN', 'AVE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (272, 1, 'AVNUE', 'AVE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (267, 1, 'AVENU', 'AVE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (268, 1, 'AVENUE', 'AVE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (399, 1, 'BUSINESS PK', 'BUSINESS PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (400, 1, 'BUSPARK', 'BUSINESS PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (401, 1, 'BUSPK', 'BUSINESS PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (402, 1, 'BUSROUTE', 'BUSINESS ROUTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (403, 1, 'BUSRT', 'BUSINESS ROUTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (404, 1, 'BUSRTE', 'BUSINESS ROUTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (406, 1, 'BX', 'BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (407, 1, 'BY', 'BYWAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (408, 2, 'BY', 'BY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (411, 1, 'BY WAY', 'BYWAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (422, 1, 'BYU', 'BAYOU', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (423, 1, 'BYWAY', 'BYWAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (424, 1, 'C', 'C', 18, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (425, 1, 'C / O', 'CARE OF', 9, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (426, 1, 'C D O', 'COMMERCIAL DEALERSHIP', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (427, 1, 'C F B', 'CANADIAN FORCES BASE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (428, 1, 'C M C', 'COMMUNITY MAIL CENTRE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (431, 1, 'C/O', 'CARE OF', 9, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (432, 1, 'CALLE', 'CALLE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (433, 1, 'CALLEJ', 'CALLEJON', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (434, 1, 'CALLEJA', 'CALLEJA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (435, 1, 'CALLEJO', 'CALLEJON', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (436, 1, 'CALLEJON', 'CALLEJON', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (437, 1, 'CALLER', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (439, 1, 'CAMINITO', 'CAMINITO', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (441, 1, 'CAMP', 'CAMP', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (442, 1, 'CAMPER PARK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (443, 1, 'CAMPER PK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (444, 1, 'CAMPUS', 'CAMPUS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (445, 1, 'CAMPUS', 'CAMPUS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (446, 1, 'CANADIAN FORCES BASE', 'CANADIAN FORCES BASE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (447, 1, 'CANYON', 'CANYON', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (448, 1, 'CANYN', 'CANYON', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (449, 1, 'CAPE', 'CAPE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (451, 1, 'CARE OF', 'CARE OF', 9, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (452, 1, 'CARR', 'CARRETERA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (453, 1, 'CARRE', 'CARRE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (454, 2, 'CARRE', 'CARRE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (455, 1, 'CARREF', 'CARREFOUR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (456, 1, 'CARREFOUR', 'CARREFOUR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (457, 1, 'CARRETERA', 'CARRETERA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (458, 1, 'CARRT', 'CARRETERA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (460, 1, 'CC', 'CIRCUIT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (461, 1, 'CDN', 'CANADIAN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (462, 1, 'CDO', 'COMMERCIAL DEALERSHIP', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (463, 1, 'CDS', 'CUL DE SAC', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (473, 3, 'CENTER', 'CENTER', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (477, 1, 'CENTRAL', 'CENTRAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (480, 3, 'CENTRE', 'CENTER', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (484, 1, 'CERCLE', 'CERCLE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (485, 2, 'CERCLE', 'CERCLE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (486, 1, 'CFB', 'CANADIAN FORCES BASE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (488, 1, 'CH', 'CHEMIN', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (489, 2, 'CH', 'CHURCH', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (490, 1, 'CHASE', 'CHASE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (491, 2, 'CHASE', 'CHASE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (492, 1, 'CHEMIN', 'CHEMIN', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (493, 1, 'CHURCH', 'CHURCH', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (494, 2, 'CHURCH', 'CHURCH', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (496, 1, 'CIRC', 'CIRCULO', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (499, 2, 'CIRCLE', 'CIRCLE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (500, 1, 'CIRCT', 'CIRCUIT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (501, 2, 'CIRCT', 'CIRCUIT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (502, 1, 'CIRCUIT', 'CIRCUIT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (503, 2, 'CIRCUIT', 'CIRCUIT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (504, 1, 'CIRCULO', 'CIRCULO', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (505, 1, 'CJA', 'CALLEJA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (506, 1, 'CJON', 'CALLEJON', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (507, 1, 'CK', 'CREEK', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (509, 2, 'CL', 'CIRCLE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (512, 3, 'CLB', 'CLUB', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (513, 1, 'CLF', 'CLIFF', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (514, 1, 'CLFS', 'CLIFFS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (515, 1, 'CLG', 'COLLEGE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (516, 1, 'CLIFF', 'CLIFF', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (517, 1, 'CLIFFS', 'CLIFFS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (518, 1, 'CLLE', 'CALLE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (519, 1, 'CLLJ', 'CALLEJON', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (520, 1, 'CLOS', 'CLOSE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (521, 2, 'CLOS', 'CLOSE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (522, 1, 'CLOSE', 'CLOSE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (523, 2, 'CLOSE', 'CLOSE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (524, 1, 'CLTN', 'COLLECTION', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (527, 3, 'CLUB', 'CLUB', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (528, 1, 'CMC', 'COMMUNITY MAIL CENTRE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (529, 1, 'CMNS', 'COMMONS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (530, 2, 'CMNS', 'COMMONS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (417, 2, 'BYPAS', 'BYP', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (421, 2, 'BYPS', 'BYP', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (419, 2, 'BYPASS', 'BYP', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (415, 2, 'BYPA', 'BYP', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (410, 2, 'BY PASS', 'BYP', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (438, 1, 'CAM', 'CAM', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (440, 1, 'CAMINO', 'CAM', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (450, 2, 'CAPE', 'CPE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (459, 1, 'CAUSEWAY', 'CSWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (483, 2, 'CENTRO', 'CTR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (479, 2, 'CENTRE', 'CTR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (476, 2, 'CENTR', 'CTR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (472, 2, 'CENTER', 'CTR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (470, 2, 'CENTE', 'CTR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (468, 2, 'CENT', 'CTR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (531, 1, 'CMP', 'CAMP', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (532, 1, 'CN', 'CONCESSION', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (533, 2, 'CN', 'CONCESSION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (534, 1, 'CNCN', 'CONNECTION', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (545, 1, 'CNTRL', 'CENTRAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (556, 1, 'CNYN', 'CANYON', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (557, 4, 'CO', 'COTE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (569, 1, 'COL', 'COLONEL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (570, 1, 'COLL', 'COLLEGE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (571, 2, 'COLL', 'COLLEGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (572, 1, 'COLLECTION', 'COLLECTION', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (573, 1, 'COLLEGE', 'COLLEGE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (574, 2, 'COLLEGE', 'COLLEGE', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (575, 3, 'COLLEGE', 'COLLEGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (576, 1, 'COLONEL', 'COLONEL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (577, 1, 'COLONIA', 'COLONIA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (578, 2, 'COLONIA', 'COLONIA', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (579, 1, 'COMMERCIAL DEALERSHIP OU', 'COMMERCIAL DEALERSHIP', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (581, 2, 'COMMON', 'COMMONS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (582, 1, 'COMMONS', 'COMMONS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (583, 2, 'COMMONS', 'COMMONS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (584, 1, 'COMMUNITY MAIL CENTRE', 'COMMUNITY MAIL CENTRE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (586, 2, 'COMN', 'COMMONS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (587, 1, 'COMP', 'COMPLEX', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (588, 1, 'COMPLEX', 'COMPLEX', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (589, 1, 'CONC', 'CONCESSION', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (590, 2, 'CONC', 'CONCESSION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (591, 1, 'CONCESSION', 'CONCESSION', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (592, 2, 'CONCESSION', 'CONCESSION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (593, 1, 'COND', 'CONDOMINIUMS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (594, 1, 'CONDO', 'CONDOMINIUMS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (595, 1, 'CONDOMINIO', 'CONDOMINIUMS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (596, 1, 'CONDOMINIUM', 'CONDOMINIUMS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (597, 1, 'CONDOMINIUMS', 'CONDOMINIUMS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (598, 1, 'CONDOS', 'CONDOMINIUMS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (599, 3, 'CONN', 'CONNECTOR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (600, 4, 'CONN', 'CONNECTOR', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (601, 1, 'CONNECTION', 'CONNECTION', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (602, 1, 'CONNECTOR', 'CONNECTOR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (603, 2, 'CONNECTOR', 'CONNECTOR', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (604, 3, 'CONNECTOR', 'CONNECTOR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (605, 1, 'CONTRACT', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (606, 2, 'CONTRACT', 'CONTRACT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (607, 1, 'COOP', 'COOPERATIVE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (608, 2, 'COOP', 'COOPERATIVE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (609, 1, 'COOPERATIVE', 'COOPERATIVE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (610, 2, 'COOPERATIVE', 'COOPERATIVE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (612, 2, 'COR', 'CORNER', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (616, 2, 'CORNER', 'CORNER', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (620, 3, 'CORNERS', 'CORNERS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (623, 3, 'CORS', 'CORNERS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (624, 1, 'CORSO', 'CORSO', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (625, 2, 'CORSO', 'CORSO', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (629, 1, 'COTE', 'COTE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (630, 2, 'COTE', 'COTE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (631, 1, 'COTTAGE', 'COTTAGE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (632, 2, 'COTTAGE', 'COTTAGE', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (633, 3, 'COTTAGE', 'COTTAGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (634, 1, 'COUNTY', 'COUNTY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (635, 2, 'COUNTY', 'COUNY ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (647, 1, 'COUR', 'COUR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (648, 1, 'COURSE', 'COURSE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (650, 2, 'COURT', 'COURT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (651, 1, 'COURT HOUSE', 'COURTHOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (652, 1, 'COURT HSE', 'COURTHOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (653, 1, 'COURT YARD', 'COURTYARD', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (654, 1, 'COURTHOUSE', 'COURTHOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (655, 2, 'COURTHOUSE', 'COURTHOUSE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (542, 2, 'CNTR', 'CTR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (538, 2, 'CNT', 'CTR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (540, 2, 'CNTER', 'CTR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (544, 2, 'CNTRE', 'CTR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (580, 1, 'COMMON', 'CMN', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (585, 1, 'COMN', 'CMN', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (536, 2, 'CNR', 'COR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (617, 3, 'CORNER', 'COR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (618, 1, 'CORNERS', 'CORS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (621, 1, 'CORS', 'CORS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (562, 2, 'CO RD', 'CO RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (550, 2, 'CNTY RD', 'CO RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (552, 2, 'CNTY ROAD', 'CO RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (642, 2, 'COUNTY ROAD', 'CO RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (640, 2, 'COUNTY RD', 'CO RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (614, 2, 'CORD', 'CO RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (564, 2, 'CO ROAD', 'CO RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (649, 1, 'COURT', 'CT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (628, 2, 'CORTE', 'CT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (656, 1, 'COURTHSE', 'COURTHOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (659, 3, 'COURTS', 'COURTS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (660, 1, 'COURTYARD', 'COURTYARD', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (661, 1, 'COURTYARDS', 'COURTYARD', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (664, 1, 'CP', 'CAMP', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (665, 1, 'CPE', 'CAPE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (666, 1, 'CPLX', 'COMPLEX', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (667, 1, 'CPO', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (668, 1, 'CPO BOX', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (673, 1, 'CRDS', 'CROSSROADS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (674, 1, 'CREEK', 'CREEK', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (677, 2, 'CRESCENT', 'CRESCENT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (679, 1, 'CRK', 'CREEK', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (684, 1, 'CROISSANT', 'CROISSANT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (685, 2, 'CROISSANT', 'CROISSANT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (686, 1, 'CROSS', 'CROSS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (687, 2, 'CROSS', 'CROSS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (689, 1, 'CROSS ROADS', 'CROSSROADS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (694, 2, 'CROSSROAD', 'CROSSROAD', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (695, 1, 'CROSSROADS', 'CROSSROADS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (697, 1, 'CRSE', 'COURSE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (707, 1, 'CRT HSE', 'COURTHOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (708, 1, 'CRTHSE', 'COURTHOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (709, 1, 'CRU', 'CRUCE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (710, 1, 'CRUC', 'CRUCE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (711, 1, 'CRUCE', 'CRUCE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (713, 1, 'CS', 'CLOSE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (716, 2, 'CT', 'CONNECTICUT', 11, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (717, 1, 'CT HSE', 'COURTHOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (718, 1, 'CT YARD', 'COURTYARD', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (719, 1, 'CT YD', 'COURTYARD', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (722, 1, 'CTHS', 'COURTHOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (723, 1, 'CTHSE', 'COURTHOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (729, 3, 'CTS', 'COURTS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (740, 1, 'CTYD', 'COURTYARD', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (741, 1, 'CU', 'COUR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (742, 1, 'CUL DE SAC', 'CUL DE SAC', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (743, 1, 'CULDESAC', 'CUL DE SAC', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (744, 1, 'CURRY RD', 'CURRY ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (745, 1, 'CURRY ROAD', 'CURRY ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (746, 1, 'CURVE', 'CURVE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (749, 1, 'CX', 'CHASE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (750, 1, 'CYN', 'CANYON', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (752, 1, 'D', 'D', 18, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (753, 2, 'D', 'D', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (754, 1, 'D B A', 'DBA', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (755, 1, 'DALE', 'DALE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (757, 1, 'DAM', 'DAM', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (758, 1, 'DBA', 'DBA', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (759, 2, 'DE', 'DE', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (760, 4, 'DE', 'DE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (761, 1, 'DE LA', 'DE LA', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (762, 1, 'DE LAS', 'DE LAS', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (763, 1, 'DE LOS', 'DE LOS', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (764, 2, 'DEL', 'DE', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (765, 1, 'DELL', 'DELL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (766, 2, 'DELL', 'DELL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (767, 1, 'DEPARTMENT', 'DEPARTMENT', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (768, 2, 'DEPARTMENT', 'DEPARTMENT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (769, 1, 'DEPT', 'DEPARTMENT', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (770, 2, 'DEPT', 'DEPARTMENT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (771, 1, 'DERE', 'DERECHO', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (772, 1, 'DERECHO', 'DERECHO', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (773, 1, 'DES', 'DES', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (774, 1, 'DEUX', '2', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (775, 2, 'DEUX', '2', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (776, 1, 'DEUXIEME', 'DEUXIEME', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (777, 1, 'DI', 'DIVERSION', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (778, 2, 'DI', 'DIVERSION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (779, 3, 'DI', 'DI', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (780, 1, 'DIV', 'DIVIDE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (781, 1, 'DIVERS', 'DIVERSION', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (782, 2, 'DIVERS', 'DIVERSION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (783, 1, 'DIVERSION', 'DIVERSION', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (784, 2, 'DIVERSION', 'DIVERSION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (785, 1, 'DIVIDE', 'DIVIDE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (786, 1, 'DL', 'DALE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (787, 2, 'DL', 'DELL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (714, 1, 'CSWY', 'CSWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (721, 2, 'CTER', 'CTR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (725, 2, 'CTR', 'CTR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (671, 1, 'CRCL', 'CIR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (672, 1, 'CRCLE', 'CIR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (682, 2, 'CRNR', 'COR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (683, 1, 'CRNRS', 'CORS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (751, 1, 'CZ', 'CORS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (736, 2, 'CTY ROAD', 'CO RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (734, 2, 'CTY RD', 'CO RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (706, 1, 'CRT', 'CT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (715, 1, 'CT', 'CT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (727, 1, 'CTS', 'CTS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (657, 1, 'COURTS', 'CTS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (663, 1, 'COVE', 'CV', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (748, 1, 'CV', 'CV', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (662, 1, 'COV', 'CV', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (680, 2, 'CRK', 'CRK', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (676, 1, 'CRESCENT', 'CRES', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (696, 1, 'CRSCNT', 'CRES', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (698, 1, 'CRSENT', 'CRES', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (702, 1, 'CRSNT', 'CRES', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (788, 1, 'DM', 'DAM', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (789, 1, 'DNS', 'DOWNS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (790, 2, 'DNS', 'DOWNS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (791, 1, 'DO', 'DOWNS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (792, 1, 'DORM', 'DORMITORY', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (793, 2, 'DORMITORY', 'DORMITORY', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (794, 1, 'DOWN', 'DOWN', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (795, 2, 'DOWN', 'DOWN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (796, 1, 'DOWNS', 'DOWNS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (797, 2, 'DOWNS', 'DOWNS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (798, 1, 'DOWNSTAIRS', 'DOWNSTAIRS', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (800, 1, 'DRAW', 'DRAW', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (801, 2, 'DRAW', 'DRAW', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (802, 1, 'DRAWER', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (805, 1, 'DRIVEWAY', 'DRIVEWAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (807, 1, 'DRWY', 'DRIVEWAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (808, 1, 'DU', 'DU', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (809, 1, 'DV', 'DIVIDE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (813, 1, 'EAST & WEST', 'EAST & WEST', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (814, 1, 'EAST WEST', 'EAST WEST', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (815, 1, 'EASTBOUND', 'EASTBOUND', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (816, 2, 'EASTBOUND', 'EASTBOUND', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (817, 1, 'ECH', 'ECHANGEUR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (818, 1, 'ECHO', 'ECHO', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (819, 2, 'ECHO', 'ECHO', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (820, 1, 'ECHANGEUR', 'ECHANGEUR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (821, 1, 'EDF', 'EDIFICIO', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (822, 1, 'EDIF', 'EDIFICIO', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (823, 1, 'EDIFICIO', 'EDIFICIO', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (824, 1, 'EIGHT', '8', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (825, 2, 'EIGHT', '8', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (826, 1, 'EIGHT MILE', 'EIGHT MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (827, 1, 'EIGHTEEN', '18', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (828, 2, 'EIGHTEEN', '18', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (829, 1, 'EIGHTEEEN MILE', 'EIGHTEEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (830, 1, 'EIGHTEENTH', '18', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (831, 2, 'EIGHTEENTH', '18TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (832, 1, 'EIGHTH', '8', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (833, 2, 'EIGHTH', '8TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (834, 1, 'EIGHTIETH', '80', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (835, 2, 'EIGHTIETH', '80TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (836, 1, 'EIGHTY', '80', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (837, 2, 'EIGHTY', '80', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (838, 1, 'EIGHTY EIGHT', '88', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (839, 2, 'EIGHTY EIGHT', '88', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (840, 1, 'EIGHTY EIGHTH', '88', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (841, 2, 'EIGHTY EIGHTH', '88TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (842, 1, 'EIGHTY FIFTH', '85', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (843, 2, 'EIGHTY FIFTH', '85TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (844, 1, 'EIGHTY FIRST', '81', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (845, 2, 'EIGHTY FIRST', '81ST', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (846, 1, 'EIGHTY FIVE', '85', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (847, 2, 'EIGHTY FIVE', '85', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (848, 1, 'EIGHTY FOUR', '84', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (849, 2, 'EIGHTY FOUR', '84', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (850, 1, 'EIGHTY FOURTH', '84', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (851, 2, 'EIGHTY FOURTH', '84TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (852, 1, 'EIGHTY NINE', '89', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (853, 2, 'EIGHTY NINE', '89', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (854, 1, 'EIGHTY NINTH', '89', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (855, 2, 'EIGHTY NINTH', '89TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (856, 1, 'EIGHTY ONE', '81', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (857, 2, 'EIGHTY ONE', '81', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (858, 1, 'EIGHTY SECOND', '82', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (859, 2, 'EIGHTY SECOND', '82ND', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (860, 1, 'EIGHTY SEVEN', '87', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (861, 2, 'EIGHTY SEVEN', '87', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (862, 1, 'EIGHTY SEVENTH', '87', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (863, 2, 'EIGHTY SEVENTH', '87TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (864, 1, 'EIGHTY SIX', '86', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (865, 2, 'EIGHTY SIX', '86', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (866, 1, 'EIGHTY SIXTH', '86', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (867, 2, 'EIGHTY SIXTH', '86TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (868, 1, 'EIGHTY THIRD', '83', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (869, 2, 'EIGHTY THIRD', '83RD', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (870, 1, 'EIGHTY THREE', '83', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (871, 2, 'EIGHTY THREE', '83', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (872, 1, 'EIGHTY TWO', '82', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (873, 2, 'EIGHTY TWO', '82', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (874, 1, 'EL', 'EL', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (876, 1, 'ELEVEN', '11', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (877, 2, 'ELEVEN', '11', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (878, 1, 'ELEVEN MILE', 'ELEVEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (879, 1, 'ELEVENTH', '11', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (880, 2, 'ELEVENTH', '11TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (881, 1, 'EMS', 'EMS', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (882, 1, 'EN', 'END', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (883, 1, 'END', 'END', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (884, 1, 'END', 'END', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (885, 1, 'ENT', 'ENTRY', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (886, 1, 'ENT', 'ENTRY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (887, 1, 'ENTRY', 'ENTRY', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (888, 2, 'ENTRY', 'ENTRY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (889, 1, 'ENTREE', 'ENTREE', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (890, 2, 'ENTREE', 'ENTREE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (891, 1, 'ES', 'ESPLANADE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (892, 1, 'ESP', 'ESPLANADE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (893, 1, 'ESPL', 'ESPLANADE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (894, 2, 'ESPL', 'ESPLANADE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (895, 3, 'ESPL', 'ESPLANADE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (896, 1, 'ESPLANADE', 'ESPLANADE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (897, 2, 'ESPLANADE', 'ESPLANADE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (898, 3, 'ESPLANADE', 'ESPLANADE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (899, 1, 'EST', 'ESTATES', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (903, 1, 'ESTATE', 'ESTATES', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (906, 1, 'ESTATES', 'ESTATES', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (909, 1, 'ESTE', 'ESTE', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (910, 2, 'ESTE', 'ESTE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (911, 1, 'ESTS', 'ESTATES', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (915, 2, 'ET', 'ETAGE', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (916, 3, 'ET', 'ET', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (917, 1, 'ETAGE', 'ETAGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (918, 2, 'ETAGE', 'ETAGE', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (919, 1, 'EX', 'EXTENDED', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (921, 1, 'EXCH', 'EXCHANGE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (875, 1, 'EL CAMINO', 'CAM', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (806, 1, 'DRV', 'DR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (799, 1, 'DR', 'DR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (803, 1, 'DRI', 'DR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (804, 1, 'DRIVE', 'DR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (810, 1, 'E', 'E', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (811, 2, 'E', 'E', 18, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (812, 1, 'EAST', 'E', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (922, 2, 'EXCH', 'EXCHANGE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (923, 1, 'EXCHANGE', 'EXCHANGE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (924, 2, 'EXCHANGE', 'EXCHANGE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (925, 3, 'EXCHANGE', 'EXCHANGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (926, 1, 'EXEC', 'EXECUTIVE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (927, 1, 'EXECUTIVE', 'EXECUTIVE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (930, 1, 'EXPRESO', 'EXPRESO', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (939, 1, 'EXTD', 'EXTENDED', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (942, 1, 'EXTENDED', 'EXTENDED', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (950, 1, 'F M', 'FARM TO MARKET ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (951, 1, 'F M RD', 'FARM TO MARKET ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (952, 2, 'F M RD', 'FARM TO MARKET ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (953, 1, 'F M ROAD', 'FARM TO MARKET ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (954, 2, 'F M ROAD', 'FARM TO MARKET ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (955, 1, 'FACTORY OUTLET', 'OUTLET', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (956, 1, 'FALL', 'FALL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (957, 1, 'FALLS', 'FALLS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (958, 1, 'FARM', 'FARM', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (959, 2, 'FARM', 'FARM', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (960, 1, 'FARM MAINTENANCE RD', 'FARM MAINTENANCE ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (961, 2, 'FARM MAINTENANCE RD', 'FARM MAINTENANCE ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (962, 1, 'FARM MARKET ROAD', 'FARM TO MARKET ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (963, 2, 'FARM MARKET ROAD', 'FARM TO MARKET ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (964, 1, 'FARM TO MARKET ROAD', 'FARM TO MARKET ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (965, 2, 'FARM TO MARKET ROAD', 'FARM TO MARKET ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (966, 1, 'FERRY', 'FERRY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (967, 1, 'FERRY CROSSING', 'FERRY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (968, 1, 'FEST', 'FESTIVAL', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (969, 1, 'FESTIVAL', 'FESTIVAL', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (970, 1, 'FIELD', 'FIELD', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (972, 1, 'FIELDS', 'FIELDS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (973, 1, 'FIFTEEN', '15', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (974, 2, 'FIFTEEN', '15', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (975, 1, 'FIFTEEN MILE', 'FIFTEEN MI', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (976, 1, 'FIFTEENTH', '15', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (977, 2, 'FIFTEENTH', '15TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (978, 1, 'FIFTH', '5', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (979, 2, 'FIFTH', '5TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (980, 1, 'FIFTIETH', '50', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (981, 2, 'FIFTIETH', '50TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (982, 1, 'FIFTY', '50', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (983, 2, 'FIFTY', '50', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (984, 1, 'FIFTY EIGHT', '58', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (985, 2, 'FIFTY EIGHT', '58', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (986, 1, 'FIFTY EIGHTH', '58', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (987, 2, 'FIFTY EIGHTH', '58TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (988, 1, 'FIFTY FIFTH', '55', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (989, 2, 'FIFTY FIFTH', '55TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (990, 1, 'FIFTY FIRST', '51', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (991, 2, 'FIFTY FIRST', '51ST', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (992, 1, 'FIFTY FIVE', '55', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (993, 2, 'FIFTY FIVE', '55', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (994, 1, 'FIFTY FOUR', '54', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (995, 2, 'FIFTY FOUR', '54', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (996, 1, 'FIFTY FOURTH', '54', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (997, 2, 'FIFTY FOURTH', '54TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (998, 1, 'FIFTY NINE', '59', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (999, 2, 'FIFTY NINE', '59', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1000, 1, 'FIFTY NINTH', '59', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1001, 2, 'FIFTY NINTH', '59TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1002, 1, 'FIFTY ONE', '51', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1003, 2, 'FIFTY ONE', '51', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1004, 1, 'FIFTY SECOND', '52', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1005, 2, 'FIFTY SECOND', '52ND', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1006, 1, 'FIFTY SEVEN', '57', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1007, 2, 'FIFTY SEVEN', '57', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1008, 1, 'FIFTY SEVENTH', '57', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1009, 2, 'FIFTY SEVENTH', '57TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1094, 1, 'FOUR', '4', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1010, 1, 'FIFTY SIX', '56', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1011, 2, 'FIFTY SIX', '56', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1012, 1, 'FIFTY SIXTH', '56', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1013, 2, 'FIFTY SIXTH', '56TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1014, 1, 'FIFTY THIRD', '53', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1015, 2, 'FIFTY THIRD', '53RD', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1016, 1, 'FIFTY THREE', '53', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1017, 2, 'FIFTY THREE', '53', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1018, 1, 'FIFTY TWO', '52', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1019, 2, 'FIFTY TWO', '52', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1020, 1, 'FIRST', '1', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1021, 2, 'FIRST', '1ST', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1022, 1, 'FIVE', '5', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1023, 2, 'FIVE', '5', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1024, 1, 'FIVE CEDARS', 'FIVE CEDARS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1025, 1, 'FIVE CORNERS', 'FIVE CORNERS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1026, 1, 'FIVE MILE', 'FIVE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1027, 1, 'FIVE POINTS', 'FIVE POINTS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1028, 1, 'FIVE TOWN', 'FIVE TOWN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1029, 1, 'FL', 'FL', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1030, 1, 'FLAT', 'FLAT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1031, 1, 'FLD', 'FIELD', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1032, 1, 'FLDS', 'FIELDS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1033, 1, 'FLLS', 'FALLS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1034, 1, 'FLOOR', 'FL', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1035, 2, 'FLOOR', 'FL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1036, 1, 'FLR', 'FL', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1037, 1, 'FLS', 'FALLS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1038, 1, 'FLT', 'FLAT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1039, 1, 'FLTS', 'FLATS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1040, 1, 'FM', 'FARM TO MARKET ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1041, 1, 'FM RD', 'FARM TO MARKET ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1042, 2, 'FM RD', 'FARM TO MARKET ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1043, 1, 'FM ROAD', 'FARM TO MARKET ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1044, 2, 'FM ROAD', 'FARM TO MARKET ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1045, 1, 'FMRD', 'FARM TO MARKET ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1046, 2, 'FMRD', 'FARM TO MARKET ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1047, 1, 'FORD', 'FORD', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1048, 1, 'FOREST', 'FOREST', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1049, 1, 'FORGE', 'FORGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (936, 1, 'EXPY', 'EXPY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (935, 1, 'EXPWY', 'EXPY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (934, 1, 'EXPWAY', 'EXPY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (932, 1, 'EXPRESSWAY', 'EXPY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (949, 1, 'EXWY', 'EXPY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1050, 1, 'FORK', 'FORK', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1051, 1, 'FORKS', 'FORKS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1052, 1, 'FORT', 'FORT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1053, 1, 'FORTIETH', '40', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1054, 2, 'FORTIETH', '40TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1055, 1, 'FORTS', 'FORT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1056, 1, 'FORTY', '40', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1057, 2, 'FORTY', '40', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1058, 1, 'FORTY EIGHT', '48', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1059, 2, 'FORTY EIGHT', '48', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1060, 1, 'FORTY EIGHTH', '48', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1061, 2, 'FORTY EIGHTH', '48TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1062, 1, 'FORTY FIFTH', '45', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1063, 2, 'FORTY FIFTH', '45TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1064, 1, 'FORTY FIRST', '41', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1065, 2, 'FORTY FIRST', '41ST', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1066, 1, 'FORTY FIVE', '45', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1067, 2, 'FORTY FIVE', '45', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1068, 1, 'FORTY FOUR', '44', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1069, 2, 'FORTY FOUR', '44', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1070, 1, 'FORTY FOURTH', '44', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1071, 2, 'FORTY FOURTH', '44TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1072, 1, 'FORTY NINE', '49', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1073, 2, 'FORTY NINE', '49', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1074, 1, 'FORTY NINTH', '49', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1075, 2, 'FORTY NINTH', '49TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1076, 1, 'FORTY ONE', '41', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1077, 2, 'FORTY ONE', '41', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1078, 1, 'FORTY SECOND', '42', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1079, 2, 'FORTY SECOND', '42ND', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1080, 1, 'FORTY SEVEN', '47', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1081, 2, 'FORTY SEVEN', '47', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1082, 1, 'FORTY SEVENTH', '47', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1083, 2, 'FORTY SEVENTH', '47TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1084, 1, 'FORTY SIX', '46', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1085, 2, 'FORTY SIX', '46', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1086, 1, 'FORTY SIXTH', '46', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1087, 2, 'FORTY SIXTH', '46TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1088, 1, 'FORTY THIRD', '43', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1089, 2, 'FORTY THIRD', '43RD', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1090, 1, 'FORTY THREE', '43', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1091, 2, 'FORTY THREE', '43', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1092, 1, 'FORTY TWO', '42', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1093, 2, 'FORTY TWO', '42', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1095, 2, 'FOUR', '4', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1096, 1, 'FOUR CORNERS', 'FOUR CORNERS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1097, 1, 'FOUR FLAGS', 'FOUR FLAGS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1098, 1, 'FOUR MILE', 'FOUR MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1099, 1, 'FOURTEEN', '14', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1100, 2, 'FOURTEEN', '14', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1101, 1, 'FOURTEEN MILE', 'FOURTEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1102, 1, 'FOURTEENTH', '14', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1103, 2, 'FOURTEENTH', '14', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1104, 1, 'FOURTH', '4', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1105, 2, 'FOURTH', '4TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1106, 1, 'FPO', 'FPO', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1107, 1, 'FRD', 'FORD', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1110, 1, 'FRG', 'FORGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1111, 1, 'FRK', 'FORK', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1112, 1, 'FRKS', 'FORKS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1113, 1, 'FRNT', 'FRONT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1114, 2, 'FRNT', 'FRONT', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1115, 1, 'FROM', 'FROM', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1116, 1, 'FRONT', 'FRONT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1117, 2, 'FRONT', 'FRONT', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1118, 3, 'FRONT', 'FRONT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1119, 1, 'FRONTAGE', 'FRONT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1120, 1, 'FRST', 'FOREST', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1121, 2, 'FRST', 'FOREST', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1122, 1, 'FRT', 'FORT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1125, 1, 'FRY', 'FERRY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1126, 1, 'FS RD', 'FOREST SERVICE ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1127, 1, 'FT', 'FORT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1128, 1, 'FWD', 'FOUR WHEEL DRIVE TRAIL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1130, 1, 'FX', 'FOX', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1131, 1, 'G DEL', 'GENERAL DELIVERY', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1132, 1, 'G DELIVERY', 'GENERAL DELIVERY', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1134, 1, 'GALLERIA', 'GALLERIA', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1135, 2, 'GALLERIA', 'GALLERIA', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1136, 1, 'GALLERIE', 'GALLERIA', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1137, 2, 'GALLERIE', 'GALLERIA', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1138, 1, 'GALR', 'GALLERIA', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1139, 1, 'GARDEN', 'GARDEN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1140, 1, 'GARDENS', 'GARDENS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1143, 1, 'GATE', 'GATE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1267, 1, 'HL', 'HILL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1144, 2, 'GATE', 'GATE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1145, 1, 'GATEWAY', 'GATEWAY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1147, 1, 'GD', 'GENERAL DELIVERY', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1148, 2, 'GD', 'GROUNDS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1149, 1, 'GDN', 'GARDEN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1151, 1, 'GDNS', 'GARDEN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1154, 1, 'GDS', 'GARDEN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1156, 1, 'GEN D', 'GENERAL DELIVERY', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1157, 1, 'GEN DEL', 'GENERAL DELIVERY', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1158, 1, 'GEN DELIVERY', 'GENERAL DELIVERY', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1159, 1, 'GENDEL', 'GENERAL DELIVERY', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1160, 1, 'GENERAL D', 'GENERAL DELIVERY', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1161, 1, 'GENERAL DEL', 'GENERAL DELIVERY', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1162, 1, 'GENERAL DELIVERY', 'GENERAL DELIVERY', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1164, 1, 'GLADE', 'GLADE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1165, 2, 'GLADE', 'GLADE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1166, 1, 'GLEN', 'GLEN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1168, 1, 'GLN', 'GLEN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1170, 1, 'GNDL', 'GENERAL DELIVERY', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1171, 1, 'GOV', 'GOVERNOR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1172, 1, 'GOVERNOR', 'GOVERNOR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1173, 1, 'GPO', 'GPO', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1174, 1, 'GR', 'GROUND', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1176, 1, 'GREEN', 'GREEN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1178, 1, 'GREENE RD', 'GREENE ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1179, 1, 'GREENE ROAD', 'GREENE ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1180, 1, 'GRN', 'GREEN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1123, 1, 'FRWAY', 'FWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1124, 1, 'FRWY', 'FWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1129, 1, 'FWY', 'FWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1108, 1, 'FREEWAY', 'FWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1182, 1, 'GRNDS', 'GROUNDS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1183, 2, 'GRNDS', 'GROUNDS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1184, 1, 'GROUND', 'GROUND', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1185, 1, 'GROUNDS', 'GROUNDS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1186, 2, 'GROUNDS', 'GROUNDS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1187, 1, 'GROVE', 'GROVE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1189, 1, 'GRV', 'GROVE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1191, 1, 'GT', 'GATE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1192, 1, 'GTWAY', 'GATEWAY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1194, 1, 'GTWY', 'GATEWAY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1197, 1, 'H C', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1198, 1, 'H C R', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1199, 1, 'H CONT', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1200, 1, 'H CONTRACT', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1201, 1, 'HALF', 'HALF', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1202, 1, 'HALL', 'HALL', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1203, 2, 'HALL', 'HALL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1204, 1, 'HANGER', 'HANGER', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1205, 2, 'HANGER', 'HANGER', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1206, 1, 'HARBOR', 'HARBOR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1207, 1, 'HARBOUR', 'HARBOR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1210, 1, 'HARBR', 'HARBOR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1213, 1, 'HAVEN', 'HAVEN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1214, 1, 'HBR', 'HARBOR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1217, 1, 'HC', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1218, 1, 'HC RT', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1219, 1, 'HC RTE', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1220, 1, 'HCO', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1221, 1, 'HCR', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1222, 1, 'HCRT', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1223, 1, 'HEIGHT', 'HEIGHTS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1224, 1, 'HEIGHTS', 'HEIGHTS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1227, 1, 'HGHLDS', 'HIGHLANDS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1228, 2, 'HGHLDS', 'HIGHLANDS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1229, 1, 'HGT', 'HEIGHTS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1232, 1, 'HGTS', 'HEIGHTS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1237, 1, 'HGWY CONTRACT', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1238, 1, 'HGWY FM', 'FARM TO MARKET ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1241, 1, 'HGY FM', 'FARM TO MARKET ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1244, 1, 'HIGH CONT', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1245, 1, 'HIGH CONTRACT', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1246, 1, 'HIGHLANDS', 'HIGHLANDS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1247, 2, 'HIGHLANDS', 'HIGHLANDS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1250, 1, 'HIGHWAY CONT', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1251, 1, 'HIGHWAY CONTRACT', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1252, 1, 'HIGHWAY CONTRACT ROUTE', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1253, 1, 'HIGHWAY FM', 'FARM TO MARKET ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1256, 1, 'HIGHWY FM', 'FARM TO MARKET ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1257, 1, 'HILL', 'HILL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1259, 1, 'HILLS', 'HILLS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1262, 1, 'HIWAY CONTRACT', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1263, 1, 'HIWAY FM', 'FARM TO MARKET ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1266, 1, 'HIWY FM', 'FARM TO MARKET ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1269, 1, 'HLLW', 'HOLLOW', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1271, 1, 'HLS', 'HILLS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1272, 1, 'HNGR', 'HANGER', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1273, 2, 'HNGR', 'HANGER', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1275, 2, 'H0', 'HOLLOW', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1276, 1, 'HOL', 'HOLLOW', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1278, 1, 'HOLLOW', 'HOLLOW', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1280, 1, 'HOLW', 'HOLLOW', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1282, 1, 'HOME', 'HOME', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1283, 2, 'HOME', 'HOME', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1284, 1, 'HOMES', 'HOME', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1285, 1, 'HOSP', 'HOSPITAL', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1286, 1, 'HOSPITAL', 'HOSPITAL', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1287, 1, 'HOTEL', 'HOTEL', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1288, 2, 'HOTEL', 'HOTEL', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1289, 1, 'HOUS', 'HOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1290, 2, 'HOUS', 'HOUSE', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1291, 1, 'HOUSE', 'HOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1292, 2, 'HOUSE', 'HOUSE', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1293, 3, 'HOUSE', 'HOUSE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1294, 1, 'HOUSING PROJ', 'PROJECTS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1295, 1, 'HOUSING PROJECTS', 'PROJECTS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1296, 1, 'HRBR', 'HARBOR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1299, 1, 'HRBOR', 'HARBOR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1302, 1, 'HSE', 'HOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1303, 2, 'HSE', 'HOUSE', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1304, 1, 'HSE PROJ', 'PROJECTS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1305, 1, 'HSE PROJECTS', 'PROJECTS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1306, 1, 'HT', 'HEIGHTS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1190, 2, 'GRV', 'GRV', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1196, 1, 'GV', 'GRV', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1188, 2, 'GROVE', 'GRV', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1211, 2, 'HARBR', 'HBR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1297, 2, 'HRBR', 'HBR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1300, 2, 'HRBOR', 'HBR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1208, 2, 'HARBOUR', 'HBR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1215, 2, 'HBR', 'HBR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1216, 3, 'HBR', 'HBR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1233, 2, 'HGTS', 'HTS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1307, 2, 'HT', 'HTS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1225, 2, 'HEIGHTS', 'HTS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1230, 2, 'HGT', 'HTS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1236, 2, 'HGWY', 'HWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1243, 2, 'HI', 'HWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1255, 2, 'HIGHWY', 'HWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1265, 2, 'HIWY', 'HWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1309, 1, 'HTL', 'HOTEL', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1310, 2, 'HTL', 'HOTEL', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1311, 1, 'HTS', 'HEIGHTS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1314, 1, 'HUI RD', 'HUI ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1315, 1, 'HUI ROAD', 'HUI ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1316, 1, 'HVN', 'HAVEN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1321, 1, 'HWC', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1324, 1, 'HWY CONT', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1325, 1, 'HWY CONTRACT', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1326, 1, 'HWY FM', 'FARM TO MARKET ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1327, 1, 'HWYS', 'HIGHWAYS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1330, 1, 'HY CONT', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1331, 1, 'HY CONTRACT', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1334, 1, 'I', 'INTERSTATE HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1336, 1, 'I H', 'INTERSTATE HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1337, 1, 'IC', 'INDUSTRIAL PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1338, 1, 'ICHG', 'INTERCHANGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1339, 1, 'IH', 'INTERSTATE HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1340, 1, 'ILE', 'ILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1341, 2, 'ILE', 'ILE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1342, 1, 'IM', 'IMPASSE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1343, 1, 'IMM', 'IMMEUBLE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1344, 2, 'IMM', 'IMMEUBLE', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1345, 1, 'IMMEUBLE', 'IMMEUBLE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1346, 2, 'IMMEUBLE', 'IMMEUBLE', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1347, 1, 'IMP', 'IMPASSE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1348, 1, 'IMPASSE', 'IMPASSE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1349, 1, 'IN CARE OF', 'CARE OF', 9, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1350, 1, 'INCTR', 'INDUSTRIAL PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1351, 1, 'IND PARK', 'INDUSTRIAL PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1352, 1, 'IND PK', 'INDUSTRIAL PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1353, 1, 'INDC', 'INDUSTRIAL PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1354, 1, 'INDL', 'INDUSTRIAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1355, 1, 'INDL CTR', 'INDUSTRIAL PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1356, 1, 'INDL PARK', 'INDUSTRIAL PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1357, 1, 'INDL PK', 'INDUSTRIAL PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1358, 1, 'INDUSTRIAL', 'INDUSTRIAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1359, 1, 'INDUSTRIAL CENTER', 'INDUSTRIAL PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1360, 1, 'INDUSTRIAL CTR', 'INDUSTRIAL PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1361, 1, 'INDUSTRIAL PARK', 'INDUSTRIAL PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1362, 1, 'INDUSTRIAL PK', 'INDUSTRIAL PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1363, 1, 'INLET', 'INLET', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1364, 1, 'INLT', 'INLET', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1365, 1, 'INN', 'INN', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1366, 2, 'INN', 'INN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1367, 1, 'INPK', 'INDUSTRIAL PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1368, 1, 'INT L', 'INTERNATIONAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1369, 1, 'INTE', 'INTERIOR', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1370, 1, 'INTERCHANGE', 'INTERCHANGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1371, 1, 'INTERIOR', 'INTERIOR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1372, 1, 'INTERIOR', 'INTERIOR', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1373, 1, 'INTERNATIONAL', 'INTERNATIONAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1374, 1, 'INTERSECTION', 'INTERSECTION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1375, 1, 'INTERSTATE', 'INTERSTATE HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1376, 2, 'INTERSTATE', 'INTERSTATE HIGHWAY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1377, 1, 'INTERSTATE HIGHWAY', 'INTERSTATE HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1378, 2, 'INTERSTATE HIGHWAY', 'INTERSTATE HIGHWAY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1379, 1, 'INTERSTATE HWY', 'INTERSTATE HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1380, 2, 'INTERSTATE HWY', 'INTERSTATE HIGHWAY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1381, 1, 'INSTITUTE', 'INSTITUTE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1382, 2, 'INSTITUTE', 'INSTITUTE', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1383, 3, 'INSTITUTE', 'INSTITUTE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1384, 1, 'INTL', 'INTERNATIONAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1385, 1, 'INTR', 'INTERSECTION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1386, 1, 'IP', 'INDUSTRIAL PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1387, 1, 'IPRK', 'INDUSTRIAL PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1388, 1, 'IS', 'INTERSTATE HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1389, 2, 'IS', 'ISLE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1391, 1, 'ISLAND', 'ISLAND', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1393, 1, 'ISLANDS', 'ISLANDS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1394, 1, 'ISLE', 'ISLE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1395, 1, 'ISLES', 'ISLES', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1396, 1, 'IZQU', 'IZQUIERDO', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1397, 1, 'IZQUIERDO', 'IZQUIERDO', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1398, 1, 'J F K', 'JOHN F KENNEDY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1399, 1, 'J F KENNEDY', 'JOHN F KENNEDY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1400, 1, 'JA', 'JARDIN', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1401, 1, 'JAF', 'JAF', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1402, 1, 'JAF BOX', 'JAF BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1403, 1, 'JAF STATION', 'JAF STATION', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1404, 1, 'JARDIN', 'JARDIN', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1405, 2, 'JARDIN', 'JARDIN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1408, 3, 'JCT', 'JUNCTION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1411, 3, 'JCTION', 'JUNCTION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1414, 3, 'JCTN', 'JUNCTION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1415, 1, 'JEEP TRAIL', 'JEEP TRAIL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1416, 1, 'JEEP TRL', 'JEEP TRAIL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1417, 1, 'JFK', 'JOHN F KENNEDY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1420, 3, 'JNCT', 'JUNCTION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1421, 1, 'JOHN F KENNEDY', 'JOHN F KENNEDY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1424, 3, 'JUNC', 'JUNCTION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1427, 3, 'JUNCT', 'JUNCTION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1430, 3, 'JUNCTION', 'JUNCTION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1433, 3, 'JUNCTN', 'JUNCTION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1312, 2, 'HTS', 'HTS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1318, 2, 'HW', 'HWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1333, 2, 'HYWY', 'HWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1329, 2, 'HY', 'HWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1323, 2, 'HWY', 'HWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1320, 2, 'HWAY', 'HWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1390, 3, 'IS', 'IS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1392, 2, 'ISLAND', 'IS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1406, 1, 'JCT', 'JCT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1409, 1, 'JCTION', 'JCT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1412, 1, 'JCTN', 'JCT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1425, 1, 'JUNCT', 'JCT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1431, 1, 'JUNCTN', 'JCT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1422, 1, 'JUNC', 'JCT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1428, 1, 'JUNCTION', 'JCT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1436, 3, 'JUNCTON', 'JUNCTION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1437, 1, 'K MART', 'K MART', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1438, 1, 'KEY', 'KEY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1440, 1, 'KEYSTONE ROUTE', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1441, 1, 'KEYSTONE RT', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1442, 1, 'KEYSTONE RTE', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1443, 1, 'KMART', 'K MART', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1444, 1, 'KNL', 'KNOLL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1446, 1, 'KNLS', 'KNOLLS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1449, 1, 'KNOLLS', 'KNOLLS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1451, 1, 'L B J', 'LYNDON B JOHNSON', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1452, 1, 'L B JOHNSON', 'LYNDON B JOHNSON', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1453, 1, 'L C D', 'LETTER CARRIER DEPOT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1456, 1, 'LAKE', 'LAKE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1457, 1, 'LAKES', 'LAKE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1460, 3, 'LAND', 'LANDING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1463, 3, 'LANDING', 'LANDING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1466, 3, 'LANDINGS', 'LANDING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1469, 1, 'LAS', 'LAS', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1470, 1, 'LBBY', 'LOBBY', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1471, 1, 'LBJ', 'LYNDON B JOHNSON', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1472, 1, 'LCD', 'LETTER CARRIER DEPOT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1473, 1, 'LCKS', 'LOCKS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1476, 3, 'LDG', 'LODGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1479, 3, 'LDGE', 'LODGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1481, 2, 'LE', 'LE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1482, 3, 'LE', 'LE', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1483, 1, 'LEFT', 'LEFT', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1484, 2, 'LEFT', 'LEFT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1485, 1, 'LES', 'LES', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1486, 1, 'LETTER CARRIER DEPOT', 'LETTER CARRIER DEPOT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1487, 1, 'LEVEL', 'LEVEL', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1488, 2, 'LEVEL', 'LEVEL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1489, 1, 'LF', 'LOAF', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1490, 1, 'LGT', 'LIGHT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1491, 1, 'LI', 'LINE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1492, 1, 'LIGHT', 'LIGHT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1493, 1, 'LIMITS', 'LIMITS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1494, 2, 'LIMITS', 'LIMITS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1495, 1, 'LINE', 'LINE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1496, 2, 'LINE', 'LINE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1497, 1, 'LINK', 'LINK', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1498, 2, 'LINK', 'LINK', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1499, 1, 'LK', 'LAKE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1500, 2, 'LK', 'LINK', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1501, 1, 'LKOUT', 'LOOKOUT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1502, 1, 'LKS', 'LAKE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1503, 1, 'LMTS', 'LIMITS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1504, 2, 'LMTS', 'LIMITS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1508, 3, 'LNDG', 'LANDING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1511, 3, 'LNDNG', 'LANDING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1513, 1, 'LOAF', 'LOAF', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1514, 1, 'LOBBY', 'LOBBY', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1515, 1, 'LOBBY', 'LOBBY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1516, 1, 'LOCAL', 'BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1517, 1, 'LOCAL BOX', 'BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1518, 1, 'LOCAL HCR', 'HIGHWAY CONTRACT ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1519, 1, 'LOCAL PO BOX', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1520, 1, 'LOCKBOX', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1521, 1, 'LOCKS', 'LOCKS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1524, 3, 'LODGE', 'LODGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1525, 1, 'LOOKOUT', 'LOOKOUT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1526, 2, 'LOOKOUT', 'LOOKOUT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1529, 1, 'LOS', 'LOS', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1530, 1, 'LOT', 'LOT', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1531, 2, 'LOT', 'LOT', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1532, 3, 'LOT', 'LOT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1533, 1, 'LOWER', 'LOWER', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1534, 2, 'LOWER', 'LOWER', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1535, 1, 'LOWR', 'LOWER', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1536, 2, 'LOWR', 'LOWER', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1539, 1, 'LT', 'LOT', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1540, 2, 'LT', 'LOT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1541, 3, 'LT', 'LOOKOUT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1542, 1, 'LVL', 'LEVEL', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1543, 1, 'LWR', 'LOWER', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1544, 2, 'LWR', 'LOWER', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1545, 1, 'LYNDON B JOHNSON', 'LYNDON B JOHNSON', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1546, 1, 'M H P', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1547, 1, 'M L K', 'MARTIN LUTHER KING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1548, 1, 'M L KING', 'MARTIN LUTHER KING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1549, 1, 'MAISON', 'MAISON', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1550, 2, 'MAISON', 'MAISON', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1551, 3, 'MAISON', 'MAISON', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1555, 3, 'MALL', 'MALL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1559, 3, 'MANOR', 'MANOR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1562, 1, 'MARG', 'MARGINAL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1563, 1, 'MARGINAL', 'MARGINAL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1564, 1, 'MARKET', 'MARKET', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1565, 2, 'MARKET', 'MARKET', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1566, 1, 'MARKET PL', 'MARKET', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1567, 1, 'MARKET PLACE', 'MARKET', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1434, 1, 'JUNCTON', 'JCT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1450, 4, 'KY', 'KY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1439, 2, 'KEY', 'KY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1445, 2, 'KNL', 'KNL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1448, 1, 'KNOLL', 'KNL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1447, 2, 'KNLS', 'KNLS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1506, 1, 'LNDG', 'LNDG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1464, 1, 'LANDINGS', 'LNDG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1461, 1, 'LANDING', 'LNDG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1458, 1, 'LAND', 'LNDG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1467, 1, 'LANDNG', 'LNDG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1509, 1, 'LNDNG', 'LNDG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1454, 1, 'LA', 'LN', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1468, 1, 'LANE', 'LN', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1480, 1, 'LE', 'LN', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1568, 1, 'MARKETPLACE', 'MARKET', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1569, 1, 'MART', 'MARKET', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1570, 1, 'MARTIN KING', 'MARTIN LUTHER KING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1571, 1, 'MARTIN L KING', 'MARTIN LUTHER KING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1572, 1, 'MARTIN LUTHER', 'MARTIN LUTHER KING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1573, 1, 'MARTIN LUTHER KING', 'MARTIN LUTHER KING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1574, 1, 'MARTIN LUTHER KING JR', 'MARTIN LUTHER KING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1575, 1, 'MAZE', 'MAZE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1576, 1, 'MC', 'MC', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1577, 1, 'MDWS', 'MEADOWS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1580, 1, 'MEADOW', 'MEADOW', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1582, 1, 'MEADOWS', 'MEADOWS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1584, 1, 'MED', 'MEDICAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1585, 1, 'MEDICAL', 'MEDICAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1586, 1, 'MEM', 'MEMORIAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1587, 1, 'MEMORIAL', 'MEMORIAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1588, 1, 'MERC', 'MERCADO', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1589, 1, 'MERCADO', 'MERCADO', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1591, 2, 'MEWS', 'MEWS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1593, 1, 'MH', 'MOBILE HOME', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1594, 1, 'MH CT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1595, 1, 'MH PARK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1596, 1, 'MHP', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1597, 1, 'MI', 'MILE POST', 20, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1598, 1, 'MI POST', 'MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1599, 1, 'MIDDLE', 'MIDDLE', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1600, 2, 'MIDDLE', 'MIDDLE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1601, 1, 'MILE', 'MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1602, 2, 'MILE', 'MILE POST', 20, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1603, 1, 'MILE POST', 'MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1604, 2, 'MILE POST', 'MILE POST', 20, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1605, 1, 'MILES', 'MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1606, 1, 'MILL', 'MILL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1607, 1, 'MILLS', 'MILLS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1608, 1, 'MISSION', 'MISSION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1609, 1, 'MKT', 'MARKET', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1610, 1, 'MKT PL', 'MARKET', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1611, 1, 'MKT PLACE', 'MARKET', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1612, 1, 'MKTPL', 'MARKET', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1615, 3, 'ML', 'MALL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1616, 1, 'ML KING', 'MARTIN LUTHER KING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1617, 1, 'MLK', 'MARTIN LUTHER KING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1618, 1, 'MLS', 'MILLS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1621, 3, 'MNR', 'MANOR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1623, 2, 'MNRS', 'MANOR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1624, 1, 'MNT', 'MOUNT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1625, 4, 'MO', 'MONTEE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1626, 1, 'MOB HM PK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1627, 1, 'MOB HOME PARK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1628, 1, 'MOBIL HOME PARK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1629, 1, 'MOBIL HOME TRPK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1630, 1, 'MOBILE COURT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1631, 1, 'MOBILE CT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1632, 1, 'MOBILE EST', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1633, 1, 'MOBILE ESTATE', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1634, 1, 'MOBILE HM PK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1635, 1, 'MOBILE HOME', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1636, 2, 'MOBILE HOME', 'MOBILE HOME', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1637, 1, 'MOBILE HOME PARK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1638, 1, 'MOBILE HOME PK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1639, 1, 'MOBILE HOME TRPK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1640, 1, 'MOBILE HOMES', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1641, 1, 'MOBILE PARK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1642, 1, 'MOBILE ROUTE', 'MOBILE ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1643, 1, 'MONTEE', 'MONTEE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1644, 2, 'MONTEE', 'MONTEE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1645, 1, 'MOOR', 'MOOR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1646, 2, 'MOOR', 'MOOR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1647, 1, 'MOTEL', 'MOTEL', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1649, 1, 'MOUNT', 'MOUNT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1651, 1, 'MOUNTAIN', 'MOUNTAIN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1653, 1, 'MOUNTAINS', 'MOUNTAIN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1654, 1, 'MP', 'MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1655, 2, 'MP', 'MILE POST', 20, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1656, 1, 'MR', 'MOBILE ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1657, 1, 'MS', 'MS', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1658, 1, 'MSN', 'MISSION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1659, 1, 'MT', 'MOUNT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1660, 1, 'MTD ROUTE', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1661, 1, 'MTD RT', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1662, 1, 'MTD RTE', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1663, 1, 'MTL', 'MOTEL', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1664, 1, 'MTN', 'MOUNTAIN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1665, 1, 'MTNS', 'MOUNTAIN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1668, 1, 'MURO', 'MURO', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1672, 1, 'N A B', 'NAVAL AIR STATION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1673, 2, 'N A B', 'NAVAL AIR STATION', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1674, 1, 'N A S', 'NAVAL AIR STATION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1675, 2, 'N A S', 'NAVAL AIR STATION', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1677, 1, 'N F D', 'NATL FOREST DEVELOP ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1679, 1, 'NAB', 'NAVAL AIR STATION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1680, 2, 'NAB', 'NAVAL AIR STATION', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1681, 1, 'NAS', 'NAVAL AIR STATION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1682, 2, 'NAS', 'NAVAL AIR STATION', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1683, 1, 'NATIONAL', 'NATIONAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1684, 1, 'NATL', 'NATIONAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1685, 1, 'NATL FOREST', 'NATL FOREST', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1686, 1, 'NATL FOREST DEVELOP ROAD', 'NATL FOREST DEVELOP ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1687, 1, 'NATL FOREST HIGHWAY', 'NATL FOREST HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1688, 1, 'NAVAL AIR BASE', 'NAVAL AIR STATION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1689, 2, 'NAVAL AIR BASE', 'NAVAL AIR STATION', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1690, 1, 'NAVAL AIR STATION', 'NAVAL AIR STATION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1691, 2, 'NAVAL AIR STATION', 'NAVAL AIR STATION', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1613, 1, 'ML', 'MALL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1619, 1, 'MNR', 'MNR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1669, 1, 'MW', 'MDW', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1581, 2, 'MEADOW', 'MDW', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1579, 4, 'ME', 'MEWS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1590, 1, 'MEWS', 'MEWS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1670, 1, 'N', 'N', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1671, 2, 'N', 'N', 18, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1676, 1, 'N E', 'NE', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1678, 1, 'N W', 'NW', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1692, 1, 'NAVAL BASE', 'NAVAL AIR STATION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1693, 2, 'NAVAL BASE', 'NAVAL AIR STATION', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1694, 1, 'NCK', 'NECK', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1696, 1, 'NEAR', 'NEAR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1697, 1, 'NECK', 'NECK', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1698, 1, 'NF HWY', 'NATL FOREST HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1699, 1, 'NFD', 'NATL FOREST DEVELOP ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1700, 1, 'NFD', 'NATL FOREST DEVELOP ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1701, 1, 'NFHWY', 'NATL FOREST HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1702, 1, 'NINE', '9', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1703, 2, 'NINE', '9', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1704, 1, 'NINE MILE', 'NINE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1705, 1, 'NINETEEN', '19', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1706, 2, 'NINETEEN', '19', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1707, 1, 'NINETEEN MILE', 'NINETEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1708, 1, 'NINETEENTH', '19', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1709, 2, 'NINETEENTH', '19TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1710, 1, 'NINETIETH', '90', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1711, 2, 'NINETIETH', '90TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1712, 1, 'NINETY', '90', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1713, 2, 'NINETY', '90', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1714, 1, 'NINETY EIGHT', '98', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1715, 2, 'NINETY EIGHT', '98', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1716, 1, 'NINETY EIGHTH', '98', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1717, 2, 'NINETY EIGHTH', '98TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1718, 1, 'NINETY FIFTH', '95', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1719, 2, 'NINETY FIFTH', '95TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1720, 1, 'NINETY FIRST', '91', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1721, 2, 'NINETY FIRST', '91ST', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1722, 1, 'NINETY FIVE', '95', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1723, 2, 'NINETY FIVE', '95', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1724, 1, 'NINETY FOUR', '94', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1725, 2, 'NINETY FOUR', '94', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1726, 1, 'NINETY FOURTH', '94', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1727, 2, 'NINETY FOURTH', '94TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1728, 1, 'NINETY NINE', '99', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1729, 2, 'NINETY NINE', '99', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1730, 1, 'NINETY NINTH', '99', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1731, 2, 'NINETY NINTH', '99TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1732, 1, 'NINETY ONE', '91', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1733, 2, 'NINETY ONE', '91', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1734, 1, 'NINETY SECOND', '92', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1735, 2, 'NINETY SECOND', '92ND', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1736, 1, 'NINETY SEVEN', '97', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1737, 2, 'NINETY SEVEN', '97', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1868, 1, 'PD', 'POND', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1738, 1, 'NINETY SEVENTH', '97', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1739, 2, 'NINETY SEVENTH', '97TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1740, 1, 'NINETY SIX', '96', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1741, 2, 'NINETY SIX', '96', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1742, 1, 'NINETY SIXTH', '96', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1743, 2, 'NINETY SIXTH', '96TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1744, 1, 'NINETY THIRD', '93', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1745, 2, 'NINETY THIRD', '93RD', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1746, 1, 'NINETY THREE', '93', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1747, 2, 'NINETY THREE', '93', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1748, 1, 'NINETY TWO', '92', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1749, 2, 'NINETY TWO', '92', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1750, 1, 'NINTH', '9', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1751, 2, 'NINTH', '9TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1752, 1, 'NO', '#', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1754, 3, 'NO', '#', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1756, 1, 'NORD', 'NORD', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1757, 1, 'NORD EST', 'NORD EST', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1758, 1, 'NORD OUEST', 'NORD OUEST', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1759, 1, 'NORDEST', 'NORD EST', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1760, 1, 'NORDOUEST', 'NORD OUEST', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1763, 1, 'NORTH & SOUTH', 'NORTH & SOUTH', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1765, 1, 'NORTH SOUTH', 'NORTH SOUTH', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1767, 1, 'NORTHBOUND', 'NORTHBOUND', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1768, 2, 'NORTHBOUND', 'NORTHBOUND', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1770, 1, 'NR', 'NEAR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1772, 1, 'NUMBER', '#', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1773, 2, 'NUMBER', '#', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1775, 1, 'O', '0', 18, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1776, 2, 'O', 'O', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1777, 1, 'OESTE', 'OESTE', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1778, 1, 'OF', 'OF', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1779, 1, 'OF PK', 'OFFICE PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1780, 1, 'OF PRK', 'OFFICE PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1781, 1, 'OFC', 'OFFICE', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1782, 1, 'OFC CENTER', 'OFFICE PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1783, 1, 'OFC COMPLEX', 'OFFICE PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1784, 1, 'OFC CTR', 'OFFICE PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1785, 1, 'OFC PARK', 'OFFICE PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1786, 1, 'OFC PRK', 'OFFICE PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1787, 1, 'OFFICE', 'OFFICE', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1788, 2, 'OFFICE', 'OFFICE PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1789, 1, 'OFFICE CENTER', 'OFFICE PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1790, 1, 'OFFICE COMPLEX', 'OFFICE PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1791, 1, 'OFFICE CTR', 'OFFICE PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1792, 1, 'OFFICE PARK', 'OFFICE PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1793, 1, 'OFFICE PRK', 'OFFICE PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1794, 1, 'OFFICES', 'OFFICE PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1795, 1, 'OFPK', 'OFFICE PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1796, 1, 'OFPRK', 'OFFICE PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1797, 1, 'OLD', 'OLD', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1798, 2, 'OLD', 'OLD', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1799, 4, 'ON', 'ON', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1800, 1, 'ONE', '1', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1801, 2, 'ONE', '1', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1802, 1, 'ONE HUNDRED', 'ONE HUNDRED', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1803, 2, 'ONE HUNDRED', '100', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1804, 1, 'ONE MILE', 'ONE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1805, 1, 'ORCH', 'ORCHARD', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1806, 1, 'ORCHARD', 'ORCHARD', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1808, 1, 'OTLT', 'OUTLET', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1809, 1, 'OUEST', 'OUEST', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1810, 1, 'OUTLET', 'OUTLET', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1811, 1, 'OUTLETS', 'OUTLET', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1812, 1, 'OUTS', 'OUTSIDE OF', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1813, 1, 'OUTSIDE', 'OUTSIDE OF', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1817, 1, 'P BOX', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1818, 1, 'P BX', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1819, 1, 'P H', 'PH', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1820, 1, 'P O', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1821, 1, 'P O B', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1695, 1, 'NE', 'NE', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1753, 2, 'NO', 'N', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1755, 1, 'NOR', 'N', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1761, 1, 'NORTE', 'N', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1822, 1, 'P O B X', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1823, 1, 'P O BOX', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1824, 1, 'P O BX', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1825, 1, 'P O DRAWER', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1826, 4, 'PA', 'PARADE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1827, 1, 'PAR', 'PARCELAS', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1828, 2, 'PAR', 'PARCELAS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1829, 3, 'PAR', 'PARCELAS', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1830, 1, 'PAR RD', 'PARISH ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1831, 1, 'PAR ROAD', 'PARISH ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1832, 1, 'PARADE', 'PARADE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1833, 2, 'PARADE', 'PARADE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1834, 1, 'PARADERO', 'PARADERO', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1835, 1, 'PARC', 'PARC', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1836, 2, 'PARC', 'PARC', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1837, 3, 'PARC', 'PARC', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1838, 1, 'PARCELAS', 'PARCELAS', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1839, 1, 'PARISH RD', 'PARISH ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1840, 1, 'PARISH ROAD', 'PARISH ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1841, 1, 'PARK', 'PARK', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1844, 1, 'PARK & SHOP', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1845, 1, 'PARK N SHOP', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1848, 1, 'PARQUE', 'PARQUE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1849, 1, 'PARRD', 'PARISH ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1850, 1, 'PASAJE', 'PASAJE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1851, 1, 'PASEO', 'PASEO', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1852, 1, 'PASO', 'PASO', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1853, 2, 'PASO', 'PASO', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1857, 1, 'PATHWAY', 'PATHWAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1858, 1, 'PAVILION', 'PAVILLION', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1859, 2, 'PAVILION', 'PAVILLION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1860, 1, 'PAVILIONS', 'PAVILLION', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1861, 2, 'PAVILIONS', 'PAVILLION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1862, 1, 'PAVILLION', 'PAVILLION', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1863, 2, 'PAVILLION', 'PAVILLION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1864, 1, 'PAVILLIONS', 'PAVILLION', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1865, 2, 'PAVILLIONS', 'PAVILLION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1866, 1, 'PAVL', 'PAVILLION', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1867, 2, 'PAVL', 'PAVILLION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1869, 1, 'PDA', 'PARADERO', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2939, 1, 'PENTHOUSE', 'PENTHOUSE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1870, 1, 'PENTHOUSE', 'PH', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1871, 1, 'PH', 'PH', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1873, 1, 'PIECE', 'PIECE', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1874, 2, 'PIECE', 'PIECE', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1875, 1, 'PIER', 'PIER', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1876, 2, 'PIER', 'PIER', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1877, 3, 'PIER', 'PIER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1879, 1, 'PINES', 'PINES', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1881, 1, 'PISO', 'PISO', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1882, 1, 'PISTA', 'PISTA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1883, 1, 'PK', 'PARK', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1893, 1, 'PLAIN', 'PLAINS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1894, 1, 'PLAINS', 'PLAINS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1895, 1, 'PLANTATION', 'PLANTATION', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1896, 2, 'PLANTATION', 'PLANTATION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1897, 1, 'PLATEAU', 'PLATEAU', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1898, 2, 'PLATEAU', 'PLATEAU', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1902, 1, 'PLN', 'PLAINS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1903, 1, 'PLNS', 'PLAINS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1904, 1, 'PLNT', 'PLANTATION', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1909, 1, 'PM', 'PROMENADE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1910, 1, 'PNES', 'PINES', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1911, 1, 'PO', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1912, 1, 'PO B', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1913, 1, 'PO B OX', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1914, 1, 'PO B X', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1915, 1, 'PO BOX', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1916, 1, 'PO BX', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1917, 1, 'PO DRAWER', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1918, 1, 'POB', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1919, 1, 'POBOX', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1920, 1, 'POINT', 'POINT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1921, 1, 'PORT', 'PORT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1923, 1, 'POST BOX', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1924, 1, 'POST BX', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1925, 1, 'POST OFFICE BOX', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1926, 1, 'POSTAL BOX', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1927, 1, 'POSTAL BX', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1928, 1, 'POSTAL OUTLET', 'POSTAL OUTLET', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1929, 2, 'POSTAL OUTLET', 'POSTAL OUTLET', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1930, 1, 'POSTOFFICE BOX', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1931, 1, 'POSTOFFICE BX', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1932, 1, 'POUCH', 'POST OFFICE BOX', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1934, 1, 'PR HI', 'PROVINCIAL HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1935, 1, 'PR HIGHWAY', 'PROVINCIAL HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1936, 1, 'PR HWY', 'PROVINCIAL HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1938, 1, 'PR RT', 'PROVINCIAL ROUTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1939, 1, 'PR RTE', 'PROVINCIAL ROUTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1940, 1, 'PRAIRIE', 'PRAIRIE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1941, 1, 'PREMIERE', '1', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1942, 2, 'PREMIERE', '1', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1943, 1, 'PRIVATE', 'PRIVATE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1944, 2, 'PRIVATE', 'PRIVATE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1945, 1, 'PRK', 'PARK', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1948, 1, 'PRO', 'PROFESSIONAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1949, 1, 'PROF', 'PROFESSIONAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1947, 3, 'PRK', 'PARK', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1843, 3, 'PARK', 'PARK', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1933, 4, 'PR', 'PARK', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1885, 3, 'PK', 'PARK', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1888, 1, 'PKWAY', 'PKWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1889, 1, 'PKWY', 'PKWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1872, 2, 'PH', 'PATH', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1950, 1, 'PROFESSIONAL', 'PROFESSIONAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1951, 1, 'PROJ', 'PROJECTS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1952, 1, 'PROJECTS', 'PROJECTS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1953, 1, 'PROM', 'PROMENADE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1954, 2, 'PROM', 'PROMENADE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1955, 1, 'PROMENADE', 'PROMENADE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1956, 2, 'PROMENADE', 'PROMENADE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1957, 1, 'PROVINCIAL HI', 'PROVINCIAL HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1958, 1, 'PROVINCIAL HIGHWAY', 'PROVINCIAL HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1959, 1, 'PROVINCIAL HWY', 'PROVINCIAL HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1960, 1, 'PROVINCIAL HY', 'PROVINCIAL HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1961, 1, 'PROVINCIAL ROUTE', 'PROVINCIAL ROUTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1962, 1, 'PROVINCIAL RT', 'PROVINCIAL ROUTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1963, 1, 'PROVINCIAL RTE', 'PROVINCIAL ROUTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1964, 1, 'PRQE', 'PARQUE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1965, 1, 'PRRD', 'PARISH ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1966, 1, 'PRT', 'PORT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1968, 1, 'PSC', 'PSC', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1969, 1, 'PSO', 'PASEO', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1970, 1, 'PSTA', 'PISTA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1971, 1, 'PT', 'POINT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1973, 1, 'PTE', 'PUENTE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1974, 1, 'PU', 'PLATEAU', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1975, 1, 'PUENTE', 'PUENTE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1976, 1, 'PV', 'PRIVATE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1977, 1, 'PVT', 'PRIVATE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1978, 2, 'PVT', 'PRIVATE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1979, 1, 'PW', 'PATHWAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1983, 1, 'QTRS', 'QUARTERS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1984, 1, 'QU', 'QUAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1985, 1, 'QUAI', 'QUAI', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1986, 2, 'QUAI', 'QUAI', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1987, 1, 'QUARTERS', 'QUARTERS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1988, 1, 'QUATRE', '4', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1989, 2, 'QUATRE', '3', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1990, 1, 'QUATRIEME', 'QUATRIEME', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1991, 1, 'QUAY', 'QUAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1992, 2, 'QUAY', 'QUAY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1993, 1, 'QUAY RD', 'QUAY ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1994, 1, 'QUAY ROAD', 'QUAY ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1995, 1, 'R', 'R', 18, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1996, 2, 'R', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1997, 1, 'R D', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1998, 1, 'R D NO', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1999, 1, 'R F D', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2000, 1, 'R NO', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2001, 1, 'R P O', 'POSTAL OUTLET', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2002, 2, 'R P O', 'POSTAL OUTLET', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2003, 1, 'R R', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2004, 1, 'R R NO', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2005, 1, 'R RT', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2006, 1, 'R RTE', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2009, 1, 'RA', 'RANGE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2010, 1, 'RADIAL', 'RADIAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2011, 1, 'RADL', 'RADIAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2012, 1, 'RAMAL', 'RAMAL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2014, 1, 'RAMPA', 'RAMPA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2015, 1, 'RANCH', 'RANCH', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2016, 1, 'RANCH TO MARKET ROAD', 'RANCH TO MARKET ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2017, 1, 'RANCH TO MARKET ROAD', 'RANCH TO MARKET ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2018, 1, 'RANCH RD', 'RANCH ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2019, 1, 'RANCH RD', 'RANCH ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2020, 1, 'RANCH ROAD', 'RANCH ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2021, 1, 'RANCH ROAD', 'RANCH ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2022, 1, 'RANG', 'RANG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2023, 2, 'RANG', 'RANG', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2024, 1, 'RANGE', 'RANGE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2025, 2, 'RANGE', 'RANGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2026, 1, 'RANGE ROAD', 'RANGE ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2027, 1, 'RANGE ROAD', 'RANGE ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2028, 1, 'RAPIDS', 'RAPIDS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2030, 1, 'RDG', 'RIDGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2032, 1, 'RDPT', 'ROND POINT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2033, 1, 'RDS', 'ROADS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2034, 1, 'RDWY', 'ROADWAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2036, 1, 'REAR', 'REAR', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2037, 1, 'REAR', 'REAR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2038, 1, 'RES', 'RESIDENCIA', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2039, 1, 'RES HWY', 'RESERVATION HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2040, 1, 'RESERVATION HIGHWAY', 'RESERVATION HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2041, 1, 'RESHY', 'RESERVATION HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2042, 1, 'RESIDENCIA', 'RESIDENCIA', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2043, 1, 'RESORT', 'RESORT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2044, 2, 'RESORT', 'RESORT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2045, 1, 'REST', 'REST', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2046, 1, 'REZ DE CHAUSEE', 'REZ DE CHAUSEE', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2047, 1, 'RFD', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2048, 1, 'RFD ROUTE', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2049, 1, 'RG', 'RANGE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2050, 2, 'RG', 'RANGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2051, 1, 'RGHT', 'RIGHT', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2052, 4, 'RI', 'RISE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2053, 1, 'RIDGE', 'RIDGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2055, 1, 'RIGHT', 'RIGHT', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2056, 1, 'RISE', 'RISE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2057, 1, 'RIV', 'RIVER', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2058, 1, 'RIVER', 'RIVER', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2059, 1, 'RL', 'RUELLE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2060, 1, 'RLE', 'RUELLE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2061, 1, 'RM', 'ROOM', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2062, 2, 'RM', 'ROOM', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2063, 3, 'RM', 'RANCH TO MARKET ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2064, 4, 'RM', 'RANCH TO MARKET ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2065, 1, 'RM RD', 'RANCH TO MARKET ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2066, 1, 'RM RD', 'RANCH TO MARKET ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2067, 1, 'RML', 'RAMAL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2070, 1, 'RNCH', 'RANCH', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2071, 1, 'RNG ROAD', 'RANGE ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2072, 1, 'RNG ROAD', 'RANGE ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2075, 1, 'ROADS', 'ROADS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2076, 1, 'ROADWAY', 'ROADWAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1980, 1, 'PWY', 'PKWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1982, 1, 'PY', 'PKWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2077, 1, 'ROND POINT', 'ROND POINT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2078, 1, 'ROOM', 'ROOM', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2086, 1, 'ROUTES', 'ROUTES', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2089, 1, 'RPDS', 'RAPIDS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2090, 1, 'RPO', 'POSTAL OUTLET', 14, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2091, 2, 'RPO', 'POSTAL OUTLET', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2092, 1, 'RR', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2093, 1, 'RR NO', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2094, 1, 'RRT', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2095, 1, 'RRTE', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2096, 1, 'RSRT', 'RESORT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2097, 2, 'RSRT', 'RESORT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2107, 1, 'RUELLE', 'RUELLE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2109, 2, 'RUN', 'RUN', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2110, 1, 'RURAL', 'RURAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2111, 1, 'RURAL', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2112, 1, 'RURAL ROUTE', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2113, 1, 'RURAL ROUTE NO', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2114, 1, 'RURAL RT', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2115, 1, 'RUTA', 'RUTA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2119, 1, 'S / C', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2120, 1, 'S C', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2122, 1, 'S R', 'STAR ROUTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2123, 2, 'S R', 'STAR ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2124, 1, 'S RT', 'STAR ROUTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2125, 2, 'S RT', 'STAR ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2127, 1, 'S/C', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2128, 1, 'SAINT', 'SAINT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2129, 1, 'SAINTE', 'SAINTE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2130, 1, 'SANTA FE', 'SANTA FE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2131, 1, 'SC', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2132, 1, 'SCH', 'SCHOOL', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2133, 1, 'SCHOOL', 'SCHOOL', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2134, 2, 'SCHOOL', 'SCHOOL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2136, 1, 'SEARING ROUTE', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2137, 1, 'SEARING RT', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2138, 1, 'SEARING RTE', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2139, 1, 'SECOND', '2', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2140, 2, 'SECOND', '2ND', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2141, 1, 'SEM', 'SEMINARY', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2142, 1, 'SEMINARY', 'SEMINARY', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2143, 2, 'SEMINARY', 'SEMINARY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2144, 1, 'SENDERO', 'SENDERO', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2145, 1, 'SENT', 'SENTIER', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2146, 1, 'SENTIER', 'SENTIER', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2150, 1, 'SERVICE', 'SERVICE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2154, 1, 'SEVEN', '7', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2155, 2, 'SEVEN', '7', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2156, 1, 'SEVEN CORNERS', 'SEVEN CORNERS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2157, 2, 'SEVEN CORNERS', 'SEVEN CORNERS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2158, 1, 'SEVEN MILE', 'SEVEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2159, 1, 'SEVENTEEN', '17', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2160, 2, 'SEVENTEEN', '17', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2161, 1, 'SEVENTEEN MILE', 'SEVENTEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2162, 1, 'SEVENTEENTH', '17', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2163, 2, 'SEVENTEENTH', '17TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2164, 1, 'SEVENTH', '7', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2165, 2, 'SEVENTH', '7', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2166, 1, 'SEVENTIETH', '70', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2167, 2, 'SEVENTIETH', '70TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2168, 1, 'SEVENTY', '70', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2169, 2, 'SEVENTY', '70', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2170, 1, 'SEVENTY EIGHT', '78', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2171, 2, 'SEVENTY EIGHT', '78', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2172, 1, 'SEVENTY EIGHTH', '78', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2173, 2, 'SEVENTY EIGHTH', '78TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2174, 1, 'SEVENTY FIFTH', '75', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2175, 2, 'SEVENTY FIFTH', '75TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2176, 1, 'SEVENTY FIRST', '71', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2177, 2, 'SEVENTY FIRST', '71ST', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2178, 1, 'SEVENTY FIVE', '75', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2179, 2, 'SEVENTY FIVE', '75', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2180, 1, 'SEVENTY FOUR', '74', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2181, 2, 'SEVENTY FOUR', '74', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2182, 1, 'SEVENTY FOURTH', '74', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2183, 2, 'SEVENTY FOURTH', '74TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2184, 1, 'SEVENTY NINE', '79', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2185, 2, 'SEVENTY NINE', '79', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2186, 1, 'SEVENTY NINTH', '79', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2187, 2, 'SEVENTY NINTH', '79TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2188, 1, 'SEVENTY ONE', '71', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2189, 2, 'SEVENTY ONE', '71', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2190, 1, 'SEVENTY SECOND', '72', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2191, 2, 'SEVENTY SECOND', '72ND', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2192, 1, 'SEVENTY SEVEN', '77', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2193, 2, 'SEVENTY SEVEN', '77', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2194, 1, 'SEVENTY SEVENTH', '77', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2195, 2, 'SEVENTY SEVENTH', '77TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2196, 1, 'SEVENTY SIX', '76', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2197, 2, 'SEVENTY SIX', '76', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2198, 1, 'SEVENTY SIXTH', '76', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2199, 2, 'SEVENTY SIXTH', '76TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2200, 1, 'SEVENTY THIRD', '73', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2201, 2, 'SEVENTY THIRD', '73RD', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2202, 1, 'SEVENTY THREE', '73', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2203, 2, 'SEVENTY THREE', '73', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2204, 1, 'SEVENTY TWO', '72', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2205, 2, 'SEVENTY TWO', '72', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2088, 1, 'RP', 'RAMP', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2081, 3, 'ROUTE', 'RTE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2104, 3, 'RTE', 'RTE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2087, 1, 'ROW', 'ROW', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2116, 1, 'RW', 'ROW', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2106, 1, 'RUE', 'RUE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2105, 1, 'RU', 'RUE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2108, 1, 'RUN', 'RUN', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2147, 1, 'SER RD', 'SVC RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2148, 1, 'SERV RD', 'SVC RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2149, 1, 'SERV ROAD', 'SVC RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2151, 2, 'SERVICE', 'SVC RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2117, 1, 'S', 'S', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2118, 2, 'S', 'S', 18, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2121, 1, 'S E', 'SE', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2126, 1, 'S W', 'SW', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2135, 1, 'SE', 'SE', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2206, 1, 'SH', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2207, 1, 'SH CTR', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2208, 1, 'SHC', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2209, 1, 'SHL', 'SHOAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2210, 1, 'SHLS', 'SHOALS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2211, 1, 'SHOAL', 'SHOAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2212, 1, 'SHOALS', 'SHOALS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2213, 1, 'SHOP', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2214, 1, 'SHOP CEN', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2215, 1, 'SHOP CENTER', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2216, 1, 'SHOP CTR', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2218, 1, 'SHOP MART', 'SHOPPING MART', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2219, 1, 'SHOP N SAVE', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2221, 1, 'SHOP SQ', 'SHOPPING SQUARE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2222, 1, 'SHOPETTE', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2223, 1, 'SHOPPERS', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2224, 1, 'SHOPPES', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2225, 1, 'SHOPPETTE', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2226, 1, 'SHOPPING', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2227, 1, 'SHOPPING CENT', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2228, 1, 'SHOPPING CENTE', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2229, 1, 'SHOPPING CENTER', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2230, 1, 'SHOPPING CNTR', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2231, 1, 'SHOPPING CTR', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2233, 1, 'SHOPPING PARK', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2235, 1, 'SHOPS', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2236, 1, 'SHORE', 'SHORE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2237, 1, 'SHP', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2238, 1, 'SHP CENTER', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2239, 1, 'SHP CT', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2240, 1, 'SHP CTR', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2243, 1, 'SHPCT', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2244, 1, 'SHPG', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2245, 1, 'SHPG CENTER', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2246, 1, 'SHPG CNTR', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2247, 1, 'SHPG CTR', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2250, 1, 'SHR', 'SHORE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2251, 1, 'SIDE', 'SIDE', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2252, 2, 'SIDE', 'SIDE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2253, 1, 'SIDE ROAD', 'SIDE ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2254, 1, 'SITE', 'SITE', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2255, 2, 'SITE', 'SITE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2256, 1, 'SIX', '6', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2257, 2, 'SIX', '6', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2258, 1, 'SIX MILE', 'SIX MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2259, 1, 'SIXTEEN', '16', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2260, 2, 'SIXTEEN', '16', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2261, 1, 'SIXTEEN MILE', 'SIXTEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2262, 1, 'SIXTEENTH', '16', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2263, 2, 'SIXTEENTH', '16TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2264, 1, 'SIXTH', '6', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2265, 2, 'SIXTH', '6TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2266, 1, 'SIXTIETH', '60', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2267, 2, 'SIXTIETH', '60TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2268, 1, 'SIXTY', '60', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2269, 2, 'SIXTY', '60', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2270, 1, 'SIXTY EIGHT', '68', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2271, 2, 'SIXTY EIGHT', '68', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2272, 1, 'SIXTY EIGHTH', '68', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2273, 2, 'SIXTY EIGHTH', '68TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2274, 1, 'SIXTY FIFTH', '65', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2275, 2, 'SIXTY FIFTH', '65TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2276, 1, 'SIXTY FIRST', '61', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2277, 2, 'SIXTY FIRST', '61ST', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2278, 1, 'SIXTY FIVE', '65', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2279, 2, 'SIXTY FIVE', '65', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2280, 1, 'SIXTY FOUR', '64', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2281, 2, 'SIXTY FOUR', '64', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2282, 1, 'SIXTY FOURTH', '64', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2283, 2, 'SIXTY FOURTH', '64TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2284, 1, 'SIXTY NINE', '69', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2285, 2, 'SIXTY NINE', '69', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2286, 1, 'SIXTY NINTH', '69', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2287, 2, 'SIXTY NINTH', '69TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2288, 1, 'SIXTY ONE', '61', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2289, 2, 'SIXTY ONE', '61', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2290, 1, 'SIXTY SECOND', '62', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2291, 2, 'SIXTY SECOND', '62ND', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2292, 1, 'SIXTY SEVEN', '67', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2293, 2, 'SIXTY SEVEN', '67', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2294, 1, 'SIXTY SEVENTH', '67', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2295, 2, 'SIXTY SEVENTH', '67TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2296, 1, 'SIXTY SIX', '66', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2297, 2, 'SIXTY SIX', '66', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2298, 1, 'SIXTY SIXTH', '66', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2299, 2, 'SIXTY SIXTH', '66TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2300, 1, 'SIXTY THIRD', '63', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2301, 2, 'SIXTY THIRD', '63RD', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2302, 1, 'SIXTY THREE', '63', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2303, 2, 'SIXTY THREE', '63', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2304, 1, 'SIXTY TWO', '62', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2305, 2, 'SIXTY TWO', '62', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2308, 1, 'SLIP', 'SLIP', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2309, 2, 'SLIP', 'SLIP', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2311, 1, 'SMT', 'SUMMIT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2312, 2, 'SMT', 'SHOPPING MART', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2313, 1, 'SNDR', 'SENDERO', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2315, 1, 'SOTA', 'SOTANO', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2316, 2, 'SOTA', 'SOTA', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2317, 1, 'SOTAN', 'SOTANO', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2318, 1, 'SOTANO', 'SOTANO', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2319, 1, 'SOUS SOL', 'SOUS SOL', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2323, 1, 'SOUTHBOUND', 'SOUTHBOUND', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2324, 2, 'SOUTHBOUND', 'SOUTHBOUND', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2327, 1, 'SP', 'SPACE', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2328, 2, 'SP', 'SHOPPING PLAZA', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2329, 1, 'SPACE', 'SPACE', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2330, 2, 'SPACE', 'SPACE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2331, 1, 'SPC', 'SPACE', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2332, 1, 'SPDWY', 'SPEEDWAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2314, 1, 'SO', 'S', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2310, 1, 'SM', 'MALL', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2307, 1, 'SKYWAY', 'SKWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2306, 1, 'SKWY', 'SKWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2320, 1, 'SOUTH', 'S', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2321, 1, 'SOUTH EAST', 'SE', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2322, 1, 'SOUTH WEST', 'SW', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2325, 1, 'SOUTHEAST', 'SE', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2326, 1, 'SOUTHWEST', 'SW', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2333, 1, 'SPEEDWAY', 'SPEEDWAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2334, 1, 'SPG', 'SPRING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2335, 1, 'SPGS', 'SPRING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2336, 1, 'SPR', 'SPRING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2337, 1, 'SPRG', 'SPRING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2338, 1, 'SPRING', 'SPRING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2339, 1, 'SPRINGS', 'SPRING', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2342, 3, 'SPUR', 'SPUR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2343, 1, 'SPURNGS', 'SPUR', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2354, 1, 'SR', 'STAR ROUTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2355, 2, 'SR', 'STAR ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2356, 3, 'SR', 'STAR ROUTE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2357, 4, 'SR', 'SIDE ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2358, 1, 'SRA', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2360, 1, 'SRV RTE', 'SERVICE ROUTE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2364, 1, 'SS', 'SUBURBAN SERVICE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2366, 2, 'SAINT', 'SAINT', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2371, 1, 'ST R', 'STAR ROUTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2372, 2, 'ST R', 'STAR ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2376, 2, 'ST ROUTE', 'STAR ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2378, 2, 'ST RT', 'STAR ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2380, 2, 'ST RTE', 'STAR ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2383, 3, 'STA', 'STATION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2384, 1, 'STALL', 'STALL', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2385, 2, 'STALL', 'STALL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2386, 1, 'STAR ROUTE', 'STAR ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2387, 1, 'STAR RT', 'STAR ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2390, 3, 'STAT', 'STATION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2391, 1, 'STATE', 'STATE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2404, 3, 'STATION', 'STATION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2405, 1, 'STATION FORCES', 'STATION FORCES', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2408, 3, 'STATN', 'STATION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2409, 1, 'STE', 'SUITE', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2410, 2, 'STE', 'SAINTE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2411, 1, 'STES', 'SUITES', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2416, 1, 'STLL', 'STALL', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2419, 3, 'STN', 'STATION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2420, 1, 'STN FORCES', 'STATION FORCES', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2421, 1, 'STOP', 'STOP', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2422, 2, 'STOP', 'STOP', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2423, 1, 'STOP & SHOP', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2424, 1, 'STOP & SHOP CTR', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2425, 1, 'STOR', 'STORE', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2426, 2, 'STOR', 'STORE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2427, 1, 'STORE', 'STORE', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2428, 2, 'STORE', 'STORE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2429, 3, 'STORE', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2430, 1, 'STORES', 'SHOPPING CENTER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2439, 1, 'STREAM', 'STREAM', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2441, 1, 'STREETS', 'STREETS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2442, 1, 'STRIP', 'STRIP', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2443, 2, 'STRIP', 'STRIP', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2444, 1, 'STRM', 'STREAM', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2445, 1, 'STRP', 'STRIP', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2446, 2, 'STRP', 'STRIP', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2447, 1, 'STRT', 'STAR ROUTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2448, 2, 'STRT', 'STAR ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2451, 1, 'STS', 'STREETS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2452, 1, 'STUDIO', 'STUDIO', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2453, 2, 'STUDIO', 'STUDIO', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2454, 1, 'SU', 'STE', 16, false);

INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2455, 1, 'SUBD', 'SUBDIVISION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2456, 2, 'SUBD', 'SUBDIVISION', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2457, 1, 'SUBDIV', 'SUBDIVISION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2458, 2, 'SUBDIV', 'SUBDIVISION', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2459, 1, 'SUBDIVISION', 'SUBDIVISION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2460, 2, 'SUBDIVISION', 'SUBDIVISION', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2361, 1, 'SRVC', 'SVC RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2359, 1, 'SRV RD', 'SVC RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2363, 1, 'SRVRTE', 'SVC RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2362, 1, 'SRVRD', 'SVC RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2341, 2, 'SPUR', 'SPUR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2350, 1, 'SQUARE', 'SQ', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2344, 1, 'SQ', 'SQ', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2346, 1, 'SQR', 'SQ', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2348, 1, 'SQU', 'SQ', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2352, 1, 'SQURE', 'SQ', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2438, 1, 'STRD', 'STATE RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2381, 1, 'STA', 'STA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2417, 1, 'STN', 'STA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2406, 1, 'STATN', 'STA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2402, 1, 'STATION', 'STA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2388, 1, 'STAT', 'STA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2437, 1, 'STRAVN', 'STRA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2450, 1, 'STRVNUE', 'STRA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2449, 1, 'STRVN', 'STRA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2433, 1, 'STRAV', 'STRA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2434, 1, 'STRAVE', 'STRA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2435, 1, 'STRAVEN', 'STRA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2436, 1, 'STRAVENUE', 'STRA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2432, 1, 'STRA', 'STRA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2365, 1, 'ST', 'ST', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2431, 1, 'STR', 'ST', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2440, 1, 'STREET', 'ST', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2412, 1, 'STH', 'S', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2461, 1, 'SUBURBAN ROUTE', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2462, 1, 'SUBURBAN RT', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2463, 1, 'SUBURBAN RTE', 'RURAL ROUTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2464, 1, 'SUBURBAN SERVICE', 'SUBURBAN SERVICE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2465, 1, 'SUD', 'SUD', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2466, 1, 'SUD EST', 'SUD EST', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2467, 1, 'SUD OUEST', 'SUD OUEST', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2468, 1, 'SUDEST', 'SUD EST', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2469, 1, 'SUDOUEST', 'SUD OUEST', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2470, 1, 'SUIT', 'STE', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2471, 2, 'SUIT', 'STE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2472, 1, 'SUITE', 'STE', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2473, 1, 'SUITES', 'STE', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2474, 2, 'SUITES', 'STE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2475, 1, 'SUMMIT', 'SUMMIT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2477, 1, 'SV RTE', 'SERVICE ROUTE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2481, 1, 'SWP', 'SWAMP', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2482, 1, 'TANK TRAIL', 'TANK TRAIL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2483, 1, 'TEN', '10', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2484, 2, 'TEN', '10', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2485, 1, 'TEN MILE', 'TEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2486, 1, 'TENTH', '10', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2487, 2, 'TENTH', '10TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2489, 1, 'TERM', 'TERMINAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2490, 2, 'TERM', 'TERMINAL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2491, 1, 'TERMINAL', 'TERMINAL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2492, 2, 'TERMINAL', 'TERMINAL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2494, 1, 'TERRASSE', 'TERRASSE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2495, 2, 'TERRASSE', 'TERRASSE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2497, 1, 'THE', 'THE', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2498, 1, 'THFR', 'THOROUGHFARE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2499, 1, 'THICKET', 'THICKET', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2500, 2, 'THICKET', 'THICKET', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2501, 1, 'THIRD', '3', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2502, 2, 'THIRD', '3RD', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2503, 1, 'THIRTEEN', '13', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2504, 2, 'THIRTEEN', '13', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2505, 1, 'THIRTEEN MILE', 'THIRTEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2506, 1, 'THIRTEENTH', '13', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2507, 2, 'THIRTEENTH', '13TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2508, 1, 'THIRTIETH', '30', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2509, 2, 'THIRTIETH', '30TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2510, 1, 'THIRTY', '30', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2511, 2, 'THIRTY', '30', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2512, 1, 'THIRTY EIGHT', '38', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2513, 2, 'THIRTY EIGHT', '38', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2514, 1, 'THIRTY EIGHTH', '38', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2515, 2, 'THIRTY EIGHTH', '38TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2516, 1, 'THIRTY FIFTH', '35', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2517, 2, 'THIRTY FIFTH', '35TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2518, 1, 'THIRTY FIRST', '31', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2519, 2, 'THIRTY FIRST', '31ST', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2520, 1, 'THIRTY FIVE', '35', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2521, 2, 'THIRTY FIVE', '35', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2522, 1, 'THIRTY FOURTH', '34', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2523, 2, 'THIRTY FOURTH', '34TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2524, 1, 'THIRTY FOUR', '34', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2525, 2, 'THIRTY FOUR', '34', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2526, 1, 'THIRTY NINE', '39', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2527, 2, 'THIRTY NINE', '39', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2528, 1, 'THIRTY NINTH', '39', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2529, 2, 'THIRTY NINTH', '39TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2530, 1, 'THIRTY ONE', '31', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2531, 2, 'THIRTY ONE', '31', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2532, 1, 'THIRTY SECOND', '32', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2533, 2, 'THIRTY SECOND', '32ND', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2534, 1, 'THIRTY SEVEN', '37', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2535, 2, 'THIRTY SEVEN', '37', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2536, 1, 'THIRTY SEVENTH', '37', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2537, 2, 'THIRTY SEVENTH', '37TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2538, 1, 'THIRTY SIX', '36', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2539, 2, 'THIRTY SIX', '36', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2540, 1, 'THIRTY SIXTH', '36', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2541, 2, 'THIRTY SIXTH', '36TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2542, 1, 'THIRTY THIRD', '33', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2543, 2, 'THIRTY THIRD', '33RD', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2544, 1, 'THIRTY THREE', '33', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2545, 2, 'THIRTY THREE', '33', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2546, 1, 'THIRTY TWO', '32', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2547, 2, 'THIRTY TWO', '32', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2548, 1, 'THORO', 'THOROUGHFARE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2549, 1, 'THOROFARE', 'THOROUGHFARE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2550, 1, 'THOROUGHFARE', 'THOROUGHFARE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2551, 1, 'THREE', '3', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2552, 2, 'THREE', '3', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2553, 1, 'THREE MILE', 'THREE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2557, 1, 'TK TRL', 'TANK TRAIL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2558, 1, 'TKTRL', 'TANK TRAIL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2560, 1, 'TLINE', 'TOWNLINE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2561, 1, 'TLR', 'TRAILER', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2562, 1, 'TLR COURT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2563, 1, 'TLR CRT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2564, 1, 'TLR CT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2565, 1, 'TLR PARK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2566, 1, 'TLR PK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2567, 1, 'TLR PRK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2570, 1, 'TOP', 'TOP', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2571, 2, 'TOP', 'TOP', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2572, 1, 'TOWER', 'TOWERS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2573, 2, 'TOWER', 'TOWER', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2574, 3, 'TOWER', 'TOWER', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2575, 1, 'TOWERS', 'TOWERS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2576, 2, 'TOWERS', 'TOWERS', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2577, 3, 'TOWERS', 'TOWERS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2578, 4, 'TOWERS', 'TOWERS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2579, 1, 'TOWN HIGHWAY', 'TOWN HIGHWAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2580, 2, 'TOWN HIGHWAY', 'TOWN HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2581, 1, 'TOWN HWY', 'TOWN HIGHWAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2582, 2, 'TOWN HWY', 'TOWN HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2583, 1, 'TOWN RD', 'TOWN ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2584, 2, 'TOWN RD', 'TOWN ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2585, 1, 'TOWN ROAD', 'TOWN ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2586, 2, 'TOWN ROAD', 'TOWN ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2587, 1, 'TOWNHOME', 'TOWNHOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2588, 1, 'TOWNHOMES', 'TOWNHOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2589, 1, 'TOWNHOUSE', 'TOWNHOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2476, 1, 'SUR', 'S', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2480, 1, 'SW', 'SW', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2590, 1, 'TOWNHOUSES', 'TOWNHOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2591, 1, 'TOWNLINE', 'TOWNLINE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2592, 1, 'TOWNSHIP HIGHWAY', 'TOWNSHIP HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2593, 1, 'TOWNSHIP HIWAY', 'TOWNSHIP HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2594, 1, 'TOWNSHIP HWY', 'TOWNSHIP HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2595, 1, 'TOWNSHIP RD', 'TOWNSHIP ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2596, 1, 'TOWNSHIP ROAD', 'TOWNSHIP ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2597, 1, 'TP', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2602, 1, 'TR', 'TOWNSHIP ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2604, 1, 'TR COURT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2605, 1, 'TR CRT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2606, 1, 'TR CT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2607, 1, 'TR PARK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2608, 1, 'TR PK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2609, 1, 'TR PRK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2610, 1, 'TR VILLAGE', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2611, 1, 'TR VLG', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2612, 1, 'TRACE', 'TRACE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2614, 1, 'TRACK', 'TRACK', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2617, 2, 'TRAIL', 'TRAIL', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2618, 1, 'TRAILER', 'TRAILER', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2619, 2, 'TRAILER', 'TRAILER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2620, 1, 'TRAILER COURT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2621, 1, 'TRAILER CRT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2622, 1, 'TRAILER CT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2623, 1, 'TRAILER PARK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2624, 1, 'TRAILER PK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2625, 1, 'TRAILER PRK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2626, 1, 'TRAILER VILLAGE', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2627, 1, 'TRAILER VLG', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2641, 1, 'TRL', 'TRL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2628, 1, 'TRAILERCOURT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2629, 1, 'TRAILERPARK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2630, 1, 'TRAILERS', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2632, 1, 'TRAK', 'TRACK', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2633, 1, 'TRANS CANADA', 'TRANS CANADA', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2634, 2, 'TRANS CANADA', 'TRANS CANADA', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2635, 1, 'TRANSCANADA', 'TRANS CANADA', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2636, 2, 'TRANSCANADA', 'TRANS CANADA', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2637, 1, 'TRCE', 'TRACE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2639, 1, 'TRCRT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2640, 1, 'TRCT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2642, 1, 'TRL COURT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2643, 1, 'TRL CRT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2644, 1, 'TRL CT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2645, 1, 'TRL PARK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2646, 1, 'TRL PK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2647, 1, 'TRL PRK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2648, 1, 'TRL VILLAGE', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2649, 1, 'TRL VLG', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2650, 1, 'TRLCRT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2651, 1, 'TRLCT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2652, 1, 'TRLPK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2653, 1, 'TRLPRK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2654, 1, 'TRLR', 'TRAILER', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2655, 2, 'TRLR', 'TRAILER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2656, 1, 'TRLR COURT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2657, 1, 'TRLR CRT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2658, 1, 'TRLR CT', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2659, 1, 'TRLR PARK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2660, 1, 'TRLR PK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2661, 1, 'TRLR PRK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2662, 1, 'TRLR VILLAGE', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2663, 1, 'TRLR VLG', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2664, 1, 'TRNABT', 'TURNABOUT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2666, 1, 'TROIS', '3', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2667, 2, 'TROIS', '3', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2668, 1, 'TROISIEME', 'TROISIEME', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2669, 1, 'TRPK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2670, 1, 'TRPRK', 'TRAILER PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2671, 1, 'TSSE', 'TERRASSE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2672, 2, 'TSSE', 'TERRASEE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2677, 1, 'TURNABOUT', 'TURNABOUT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2684, 1, 'TW HY', 'TOWNSHIP HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2685, 1, 'TW RD', 'TOWNSHIP ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2686, 1, 'TWELFTH', '12', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2687, 2, 'TWELFTH', '12TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2688, 1, 'TWELVE', '12', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2689, 2, 'TWELVE', '12', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2690, 1, 'TWELVE MILE', 'TWELVE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2691, 1, 'TWENTIETH', '20', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2692, 2, 'TWENTIETH', '20TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2693, 1, 'TWENTY', '20', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2694, 2, 'TWENTY', '20', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2695, 1, 'TWENTY EIGHT', '28', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2696, 2, 'TWENTY EIGHT', '28', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2697, 1, 'TWENTY EIGHTH', '28', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2698, 2, 'TWENTY EIGHTH', '28TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2699, 1, 'TWENTY FIRST', '21', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2700, 2, 'TWENTY FIRST', '21ST', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2701, 1, 'TWENTY FIFTH', '25', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2702, 2, 'TWENTY FIFTH', '25TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2703, 1, 'TWENTY FIVE', '25', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2704, 2, 'TWENTY FIVE', '25', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2705, 1, 'TWENTY FOURTH', '24', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2706, 2, 'TWENTY FOURTH', '24TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2707, 1, 'TWENTY FOUR', '24', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2708, 2, 'TWENTY FOUR', '24', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2709, 1, 'TWENTY MILE', 'TWENTY MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2710, 1, 'TWENTY NINE', '29', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2711, 2, 'TWENTY NINE', '29', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2712, 1, 'TWENTY NINTH', '29', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2713, 2, 'TWENTY NINTH', '29TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2613, 2, 'TRACE', 'TRCE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2638, 2, 'TRCE', 'TRCE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2615, 1, 'TRAFFICWAY', 'TRFY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2603, 2, 'TR', 'TRL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2714, 1, 'TWENTY ONE', '21', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2715, 2, 'TWENTY ONE', '21', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2716, 1, 'TWENTY SECOND', '22', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2717, 2, 'TWENTY SECOND', '22ND', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2718, 1, 'TWENTY SEVEN', '27', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2719, 2, 'TWENTY SEVEN', '27', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2720, 1, 'TWENTY SEVENTH', '27', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2721, 2, 'TWENTY SEVENTH', '27TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2722, 1, 'TWENTY SIX', '26', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2723, 2, 'TWENTY SIX', '26', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2724, 1, 'TWENTY SIXTH', '26', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2725, 2, 'TWENTY SIXTH', '26TH', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2726, 1, 'TWENTY THIRD', '23', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2727, 2, 'TWENTY THIRD', '23RD', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2728, 1, 'TWENTY THREE', '23', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2729, 2, 'TWENTY THREE', '23', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2730, 1, 'TWENTY THREE MILE', 'TWENTY THREE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2731, 1, 'TWENTY TWO', '22', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2732, 2, 'TWENTY TWO', '22', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2733, 1, 'TWHY', 'TOWNSHIP HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2734, 1, 'TWNH', 'TOWNHOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2735, 1, 'TWNHS', 'TOWNHOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2736, 1, 'TWNHWY', 'TOWN HIGHWAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2737, 2, 'TWNHWY', 'TOWN HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2738, 1, 'TWNRD', 'TOWN ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2739, 2, 'TWNRD', 'TOWN ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2740, 1, 'TWO', '2', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2741, 2, 'TWO', '2', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2742, 1, 'TWO MILE', 'TWO MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2743, 1, 'TWP', 'TOWNSHIP', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2744, 2, 'TWP', 'TOWNSHIP HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2745, 1, 'TWP HIGHWAY', 'TOWNSHIP HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2746, 1, 'TWP HIWAY', 'TOWNSHIP HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2747, 1, 'TWP HWY', 'TOWNSHIP HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2748, 1, 'TWP HY', 'TOWNSHIP HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2749, 1, 'TWP RD', 'TOWNSHIP ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2750, 1, 'TWP ROAD', 'TOWNSHIP ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2751, 1, 'TWPHWY', 'TOWNSHIP HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2752, 1, 'TWPHY', 'TOWNSHIP HIGHWAY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2753, 1, 'TWPRD', 'TOWNSHIP ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2754, 1, 'TWPROAD', 'TOWNSHIP ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2755, 1, 'TWR', 'TOWER', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2756, 2, 'TWR', 'TOWER', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2757, 1, 'TWRD', 'TOWNSHIP ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2758, 1, 'TWRS', 'TOWERS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2759, 2, 'TWRS', 'TOWERS', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2760, 3, 'TWRS', 'TOWERS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2761, 1, 'U', 'UNIVERSITY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2762, 2, 'U', 'U', 18, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2772, 1, 'UN', 'UNION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2773, 2, 'UN', '1', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2774, 3, 'UN', '1', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2775, 1, 'UN RD', 'UNNAMED ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2777, 1, 'UNI', 'UNIVERSITY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2778, 1, 'UNION', 'UNION', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2779, 1, 'UNIT', 'UNIT', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2780, 1, 'UNITE', 'UNITE', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2783, 1, 'UNITED STATES LOOP', 'US LOOP', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2784, 1, 'UNIV', 'UNIVERSITY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2785, 2, 'UNIV', 'UNIVERSITY', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2786, 1, 'UNIVD', 'UNIVERSITY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2787, 2, 'UNIVD', 'UNIVERSITY', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2788, 1, 'UNIVERSIDAD', 'UNIVERSIDAD', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2789, 2, 'UNIVERSIDAD', 'UNIVERSIDAD', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2790, 1, 'UNIVERSITY', 'UNIVERSITY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2791, 2, 'UNIVERSITY', 'UNIVERSITY', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2792, 3, 'UNIVERSITY', 'UNIVERSITY', 19, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2793, 1, 'UNNAMED ROAD', 'UNNAMED ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2796, 1, 'UNRD', 'UNNAMED ROAD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2797, 1, 'UNT', 'UNIT', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2798, 1, 'UP', 'UP', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2799, 2, 'UP', 'UP', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2800, 1, 'UPPER', 'UPPER', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2801, 2, 'UPPER', 'UPPER', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2802, 1, 'UPPR', 'UPPER', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2803, 2, 'UPPR', 'UPPER', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2804, 1, 'UPSTAIRS', 'UPSTAIRS', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2806, 1, 'US FOREST SERVICE ROAD', 'US FOREST SERVICE ROAD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2812, 1, 'US LOOP', 'US LOOP', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2813, 1, 'US LP', 'US LOOP', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2817, 1, 'USFS RD', 'US FOREST SERVICE RD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2818, 1, 'USFSR', 'US FOREST SERVICE RD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2822, 1, 'USLP', 'US LOOP', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2826, 1, 'VAL', 'VALLEY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2827, 1, 'VALL', 'VALLEY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2828, 1, 'VALLEY', 'VALLEY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2829, 1, 'VALLY', 'VALLEY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2830, 1, 'VER', 'VEREDA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2831, 1, 'VEREDA', 'VEREDA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2834, 1, 'VIADUCT', 'VIADUCT', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2835, 1, 'VIEW', 'VIEW', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2839, 3, 'VILL', 'VILLAGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2840, 1, 'VILLA', 'VILLA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2841, 2, 'VILLA', 'VILLA', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2794, 1, 'UNP', 'UPAS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2776, 1, 'UNDERPASS', 'UPAS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2795, 1, 'UNPS', 'UPAS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2832, 2, 'VI', 'VIA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2833, 1, 'VIA', 'VIA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2836, 2, 'VIEW', 'VW', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2837, 1, 'VILL', 'VLG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2842, 3, 'VILLA', 'VILLA', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2845, 3, 'VILLAG', 'VILLAGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2848, 3, 'VILLAGE', 'VILLAGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2849, 1, 'VILLAS', 'VILLA', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2850, 1, 'VILLE', 'VILLE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2853, 3, 'VILLG', 'VILLAGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2857, 3, 'VILLIAGE', 'VILLAGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2858, 1, 'VIS', 'VISTA', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2860, 1, 'VISTA', 'VISTA', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2862, 1, 'VIVI', 'VIVIENDA', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2863, 1, 'VIVIENDA', 'VIVIENDA', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2864, 1, 'VL', 'VILLE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2868, 3, 'VLG', 'VILLAGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2871, 3, 'VLGE', 'VILLAGE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2872, 1, 'VLLA', 'VILLA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2873, 2, 'VLLA', 'VILLA', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2874, 1, 'VLY', 'VALLEY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2875, 1, 'VOIE', 'VOIE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2876, 1, 'VRDA', 'VEREDA', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2877, 1, 'VW', 'VIEW', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2882, 1, 'WALKWAY', 'WALKWAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2883, 1, 'WALKWY', 'WALKWAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2885, 1, 'WAREHOUSE', 'WAREHOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2886, 2, 'WAREHOUSE', 'WAREHOUSE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2887, 1, 'WATERWAY', 'WATERWAY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2889, 1, 'WD', 'WYND', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2890, 1, 'WDS', 'WOODS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2892, 1, 'WELLS', 'WELLS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2894, 1, 'WESTBOUND', 'WESTBOUND', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2895, 2, 'WESTBOUND', 'WESTBOUND', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2896, 1, 'WHARF', 'WHARF', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2897, 2, 'WHARF', 'WHARF', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2898, 1, 'WHF', 'WHARF', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2899, 2, 'WHF', 'WHARF', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2900, 1, 'WHS', 'WAREHOUSE', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2901, 2, 'WHS', 'WAREHOUSE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2902, 1, 'WILDLIFE MGMT AREA', 'WILDLIFE AREA', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2904, 1, 'WKWY', 'WALKWAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2905, 1, 'WLKWY', 'WALKWAY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2906, 1, 'WLS', 'WELLS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2907, 1, 'WMA', 'WILDLIFE AREA', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2908, 1, 'WO', 'WOOD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2909, 1, 'WOOD', 'WOOD', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2910, 2, 'WOOD', 'WOOD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2911, 1, 'WOODS', 'WOODS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2912, 1, 'WTRWY', 'WATERWAY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2913, 1, 'WWY', 'WATERWAY', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2916, 1, 'WYND', 'WYND', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2920, 1, 'XRDS', 'CROSSROADS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2923, 1, 'YARD', 'YARD', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2924, 1, 'YARDS', 'YARDS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2925, 1, 'YD', 'YARD', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2926, 1, 'YDS', 'YARDS', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2927, 1, 'ZANJA', 'ZANJA', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2928, 1, 'ZERO', '0', 0, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2929, 1, 'ZERO', '0', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2930, 1, 'ZNJA', 'ZANJA', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (197, 4, 'AL', 'ALY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (196, 2, 'AL', 'ALY', 11, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (216, 2, 'ANNEX', 'ANX', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (214, 2, 'ANEX', 'ANX', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (218, 2, 'ANNX', 'ANX', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (220, 2, 'ANX', 'ANX', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (239, 2, 'ARC', 'ARC', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (241, 2, 'ARCADE', 'ARC', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2879, 1, 'W', 'W', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2880, 2, 'W', 'W', 18, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2891, 1, 'WE', 'W', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2893, 1, 'WEST', 'W', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (264, 1, 'AVE', 'AVE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (265, 1, 'AVEN', 'AVE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (298, 2, 'BEACH', 'BCH', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (289, 2, 'BCH', 'BCH', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (303, 1, 'BH', 'BCH', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (324, 2, 'BND', 'BND', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (296, 1, 'BE', 'BND', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (300, 2, 'BEND', 'BND', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (314, 2, 'BLF', 'BLF', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (319, 2, 'BLUFF', 'BLF', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (321, 1, 'BLVD', 'BLVD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (320, 1, 'BLV', 'BLVD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (304, 1, 'BL', 'BLVD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (290, 1, 'BD', 'BLVD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (338, 1, 'BOUL', 'BLVD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (339, 1, 'BOULEVARD', 'BLVD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (340, 1, 'BOULV', 'BLVD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (353, 1, 'BRG', 'BRG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (332, 1, 'BOT', 'BTM', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (334, 1, 'BOTTM', 'BTM', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (336, 1, 'BOTTOM', 'BTM', 17, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (412, 1, 'BYP', 'BYP', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (420, 1, 'BYPS', 'BYP', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (409, 1, 'BY PASS', 'BYP', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (418, 1, 'BYPASS', 'BYP', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (345, 2, 'BP', 'BYP', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (416, 1, 'BYPAS', 'BYP', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (414, 1, 'BYPA', 'BYP', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (344, 1, 'BP', 'BYP', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (466, 2, 'CEN', 'CTR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (464, 1, 'CE', 'CTR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (495, 1, 'CIR', 'CIR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (498, 1, 'CIRCLE', 'CIR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (497, 1, 'CIRCL', 'CIR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (508, 1, 'CL', 'CIR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (526, 2, 'CLUB', 'CLB', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (511, 2, 'CLB', 'CLB', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (525, 1, 'CLUB', 'CLB', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (510, 1, 'CLB', 'CLB', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (730, 1, 'CTY HIGHWAY', 'CO HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (548, 1, 'CNTY HWY', 'CO HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (547, 1, 'CNTY HIWAY', 'CO HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (546, 1, 'CNTY HIGHWAY', 'CO HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (568, 1, 'COHWY', 'CO HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (638, 1, 'COUNTY HWY', 'CO HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (560, 1, 'CO HWY', 'CO HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (559, 1, 'CO HIWAY', 'CO HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (732, 1, 'CTY HWY', 'CO HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (637, 1, 'COUNTY HIWAY', 'CO HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (558, 1, 'CO HIGHWAY', 'CO HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (636, 1, 'COUNTY HIGHWAY', 'CO HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (731, 1, 'CTY HIWAY', 'CO HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (561, 1, 'CO RD', 'CO RD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (563, 1, 'CO ROAD', 'CO RD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (733, 1, 'CTY RD', 'CO RD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (429, 1, 'C R', 'CO RD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (639, 1, 'COUNTY RD', 'CO RD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (641, 1, 'COUNTY ROAD', 'CO RD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (646, 1, 'COUNTY TRUNK', 'CO RD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (735, 1, 'CTY ROAD', 'CO RD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (670, 2, 'CR', 'CO RD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (549, 1, 'CNTY RD', 'CO RD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (551, 1, 'CNTY ROAD', 'CO RD', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (613, 1, 'CORD', 'CO RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (738, 1, 'CTY RT', 'CO RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (566, 1, 'CO RT', 'CO RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (567, 1, 'CO RTE', 'CO RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (645, 1, 'COUNTY RTE', 'CO RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (644, 1, 'COUNTY RT', 'CO RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (739, 1, 'CTY RTE', 'CO RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (626, 1, 'CORT', 'CO RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (627, 1, 'CORTE', 'CO RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (565, 1, 'CO ROUTE', 'CO RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (555, 1, 'CNTY RTE', 'CO RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (643, 1, 'COUNTY ROUTE', 'CO RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (554, 1, 'CNTY RT', 'CO RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (553, 1, 'CNTY ROUTE', 'CO RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (737, 1, 'CTY ROUTE', 'CO RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (681, 1, 'CRNR', 'COR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (615, 1, 'CORNER', 'COR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (535, 1, 'CNR', 'COR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (619, 2, 'CORNERS', 'CORS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (611, 1, 'COR', 'CORS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (622, 2, 'CORS', 'CORS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (430, 2, 'C R', 'CO RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (705, 1, 'CRST', 'CRES', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (675, 1, 'CRES', 'CRES', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (669, 1, 'CR', 'CRES', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (678, 1, 'CRESENT', 'CRES', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (487, 1, 'CG', 'XING', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (690, 1, 'CROSSING', 'XING', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (699, 1, 'CRSG', 'XING', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (703, 1, 'CRSSNG', 'XING', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2917, 1, 'XING', 'XING', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2919, 1, 'XRD', 'XRD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (693, 1, 'CROSSROAD', 'XRD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (724, 1, 'CTR', 'CTR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (541, 1, 'CNTR', 'CTR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (720, 1, 'CTER', 'CTR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (543, 1, 'CNTRE', 'CTR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (726, 1, 'CTRO', 'CTR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (475, 1, 'CENTR', 'CTR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (482, 1, 'CENTRO', 'CTR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (481, 1, 'CENTRES', 'CTR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (478, 1, 'CENTRE', 'CTR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (465, 1, 'CEN', 'CTR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (467, 1, 'CENT', 'CTR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (469, 1, 'CENTE', 'CTR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (471, 1, 'CENTER', 'CTR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (474, 1, 'CENTERS', 'CTR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (537, 1, 'CNT', 'CTR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (539, 1, 'CNTER', 'CTR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (658, 2, 'COURTS', 'CTS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (728, 2, 'CTS', 'CTS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (712, 1, 'CRV', 'CURV', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (747, 2, 'CURVE', 'CURV', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (756, 2, 'DALE', 'DL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (902, 4, 'EST', 'EST', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (905, 3, 'ESTATE', 'ESTS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (901, 3, 'EST', 'ESTS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (908, 3, 'ESTATES', 'ESTS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (913, 3, 'ESTS', 'ESTS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (914, 1, 'ET', 'ESTS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (912, 2, 'ESTS', 'ESTS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (907, 2, 'ESTATES', 'ESTS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (904, 2, 'ESTATE', 'ESTS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (900, 2, 'EST', 'ESTS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2922, 1, 'XWY', 'EXPY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2921, 1, 'XWAY', 'EXPY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (933, 1, 'EXPW', 'EXPY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (928, 1, 'EXP', 'EXPY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (929, 1, 'EXPR', 'EXPY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (931, 1, 'EXPRESS', 'EXPY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (943, 1, 'EXTENSION', 'EXT', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (945, 1, 'EXTN', 'EXT', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (940, 1, 'EXTEN', 'EXT', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (947, 1, 'EXTSN', 'EXT', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (937, 1, 'EXT', 'EXT', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (920, 2, 'EX', 'EXT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (941, 2, 'EXTEN', 'EXT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (946, 2, 'EXTN', 'EXT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (948, 2, 'EXTSN', 'EXT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (938, 2, 'EXT', 'EXT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (944, 2, 'EXTENSION', 'EXT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (971, 2, 'FIELD', 'FLD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1109, 1, 'FREEWY', 'FWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1141, 2, 'GARDENS', 'GDNS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1133, 4, 'GA', 'GDNS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1155, 2, 'GDS', 'GDNS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1152, 2, 'GDNS', 'GDNS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1578, 2, 'MDWS', 'MDWS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1150, 1, 'GDN', 'GDN', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1153, 3, 'GDNS', 'GDNS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1142, 3, 'GARDENS', 'GDNS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1167, 2, 'GLEN', 'GLN', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1169, 2, 'GLN', 'GLN', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1163, 1, 'GL', 'GLN', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1177, 2, 'GREEN', 'GRN', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1175, 2, 'GR', 'GRN', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1181, 2, 'GRN', 'GRN', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1146, 2, 'GATEWAY', 'GTWY', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1195, 2, 'GTWY', 'GTWY', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1193, 2, 'GTWAY', 'GTWY', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1212, 3, 'HARBR', 'HBR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1209, 3, 'HARBOUR', 'HBR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1298, 3, 'HRBR', 'HBR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1301, 3, 'HRBOR', 'HBR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1261, 2, 'HIWAY', 'HWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1240, 2, 'HGY', 'HWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1249, 2, 'HIGHWAY', 'HWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1258, 2, 'HILL', 'HL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1268, 2, 'HL', 'HL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1274, 1, 'HO', 'HOLW', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1281, 2, 'HOLW', 'HOLW', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1277, 2, 'HOL', 'HOLW', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1279, 2, 'H0LL0W', 'HOLW', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1270, 2, 'HLLW', 'HOLW', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1231, 3, 'HGT', 'HTS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1313, 3, 'HTS', 'HTS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1234, 3, 'HGTS', 'HTS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1226, 3, 'HEIGHTS', 'HTS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1308, 3, 'HT', 'HTS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1242, 1, 'HI', 'HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1332, 1, 'HYWY', 'HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1319, 1, 'HWAY', 'HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1322, 1, 'HWY', 'HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1248, 1, 'HIGHWAY', 'HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1260, 1, 'HIWAY', 'HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1254, 1, 'HIGHWY', 'HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1328, 1, 'HY', 'HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1235, 1, 'HGWY', 'HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1239, 1, 'HGY', 'HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1264, 1, 'HIWY', 'HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1317, 1, 'HW', 'HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1335, 2, 'I', 'I-', 18, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1423, 2, 'JUNC', 'JCT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1429, 2, 'JUNCTION', 'JCT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1432, 2, 'JUNCTN', 'JCT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1410, 2, 'JCTION', 'JCT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1413, 2, 'JCTN', 'JCT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1419, 2, 'JNCT', 'JCT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1407, 2, 'JCT', 'JCT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1426, 2, 'JUNCT', 'JCT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1435, 2, 'JUNCTON', 'JCT', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1418, 1, 'JNCT', 'JCT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1505, 1, 'LN', 'LN', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1523, 2, 'LODGE', 'LDG', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1475, 2, 'LDG', 'LDG', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1478, 2, 'LDGE', 'LDG', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1455, 2, 'LA', 'LN', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1507, 2, 'LNDG', 'LNDG', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1459, 2, 'LAND', 'LNDG', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1510, 2, 'LNDNG', 'LNDG', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1465, 2, 'LANDINGS', 'LNDG', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1462, 2, 'LANDING', 'LNDG', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1477, 1, 'LDGE', 'LDG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1522, 1, 'LODGE', 'LDG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1474, 1, 'LDG', 'LDG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1527, 1, 'LOOP', 'LOOP', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1528, 2, 'LOOP', 'LOOP', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1538, 2, 'LP', 'LOOP', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1512, 1, 'LO', 'LOOP', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1537, 1, 'LP', 'LOOP', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1556, 1, 'MALL IN', 'MALL', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2232, 1, 'SHOPPING MALL', 'MALL', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2217, 1, 'SHOP MALL', 'MALL', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1552, 1, 'MAL', 'MALL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2241, 1, 'SHP ML', 'MALL', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1554, 2, 'MALL', 'MALL', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2248, 1, 'SHPML', 'MALL', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1614, 2, 'ML', 'MALL', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1553, 1, 'MALL', 'MALL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1557, 1, 'MANOR', 'MNR', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1583, 2, 'MEADOWS', 'MDWS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1592, 3, 'MEWS', 'MEWS', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1620, 2, 'MNR', 'MNR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1560, 1, 'MANORS', 'MNR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1558, 2, 'MANOR', 'MNR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1622, 1, 'MNRS', 'MNR', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1648, 1, 'MOTORWAY', 'MTWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1666, 1, 'MTWY', 'MTWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1667, 1, 'MU', 'MT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1650, 2, 'MOUNT', 'MT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1652, 2, 'MOUNTAIN', 'MTN', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1807, 2, 'ORCHARD', 'ORCH', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1814, 1, 'OVAL', 'OVAL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1815, 1, 'OVERPASS', 'OPAS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1816, 1, 'OVPS', 'OPAS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1884, 2, 'PK', 'PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1946, 2, 'PRK', 'PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1842, 2, 'PARK', 'PARK', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1981, 1, 'PWKY', 'PKWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1846, 1, 'PARKWAY', 'PKWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1890, 1, 'PKY', 'PKWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1847, 1, 'PARKWY', 'PKWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1887, 1, 'PKW', 'PKWY', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1854, 1, 'PASS', 'PASS', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1855, 1, 'PASSAGE', 'PSGE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1856, 1, 'PATH', 'PATH', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1878, 1, 'PIKE', 'PIKE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1886, 1, 'PKE', 'PIKE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1880, 2, 'PINES', 'PNES', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1892, 1, 'PLACE', 'PL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1901, 1, 'PLC', 'PL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1891, 1, 'PL', 'PL', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1899, 1, 'PLAZA', 'PLZ', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1907, 1, 'PLZA', 'PLZ', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1905, 1, 'PLZ', 'PLZ', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1906, 2, 'PLZ', 'PLZ', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1908, 2, 'PLZA', 'PLZ', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2242, 1, 'SHP PL', 'PLZ', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2249, 1, 'SHPPL', 'PLZ', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1900, 2, 'PLAZA', 'PLZ', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2220, 1, 'SHOP PLZ', 'PLZ', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2234, 1, 'SHOPPING PLAZA', 'PLZ', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1972, 2, 'PT', 'PT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1922, 2, 'PORT', 'PRT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1967, 2, 'PRT', 'PRT', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2068, 1, 'RMP', 'RAMP', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2013, 1, 'RAMP', 'RAMP', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2031, 2, 'RDG', 'RDG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2054, 2, 'RIDGE', 'RDG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2035, 1, 'RE', 'RDG', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2074, 1, 'ROAD', 'RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2029, 1, 'RD', 'RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2073, 1, 'RO', 'RTE', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2103, 2, 'RTE', 'RTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2007, 1, 'R T', 'RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2008, 2, 'R T', 'RTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2079, 1, 'ROUTE', 'RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2766, 1, 'U S HIWAY', 'US HWY', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (1, 1, '#', '#', 16, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2, 2, '#', '#', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (3, 1, '&', 'AND', 13, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (4, 2, '&', 'AND', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (5, 3, '&', 'AND', 7, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (6, 1, '-', '-', 9, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (7, 1, '1 / 2', '1/2', 25, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (8, 1, '1 / 2 MILE', '1/2 MI', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (9, 1, '1 / 3', '1/3', 25, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (10, 1, '1 / 4', '1/4', 25, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (11, 1, '1 MI', 'ONE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (12, 1, '1 MILE', 'ONE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (13, 1, '1/2', '1/2', 25, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (14, 1, '1/2 MILE', '1/2 MI', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (15, 1, '1/3', '1/3', 25, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (16, 1, '1/4', '1/4', 25, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (17, 1, '10 MI', 'TEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (18, 1, '10 MILE', 'TEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (19, 1, '10MI', 'TEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (20, 1, '100 MILE', 'ONE HUNDRED MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (21, 1, '11 MI', 'ELEVEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (22, 1, '11 MILE', 'ELEVEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (23, 1, '11MI', 'ELEVEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (24, 1, '12 MI', 'TWELVE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (25, 1, '12 MILE', 'TWELVE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (26, 1, '12MI', 'TWELVE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (27, 1, '13 MI', 'THIRTEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (28, 1, '13 MILE', 'THIRTEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (29, 1, '13MI', 'THIRTEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (30, 1, '14 MI', 'FOURTEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (31, 1, '14 MILE', 'FOURTEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (32, 1, '14MI', 'FOURTEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (33, 1, '15 MI', 'FIFTEEN MI', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (34, 1, '15 MILE', 'FIFTEEN MI', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (35, 1, '15MI', 'FIFTEEN MI', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (36, 1, '16 MI', 'SIXTEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (37, 1, '16 MILE', 'SIXTEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (38, 1, '16MI', 'SIXTEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (39, 1, '17 MI', 'SEVENTEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (40, 1, '17 MILE', 'SEVENTEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (41, 1, '17MI', 'SEVENTEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (42, 1, '18 MI', 'EIGHTEEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (43, 1, '18 MILE', 'EIGHTEEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (44, 1, '18MI', 'EIGHTEEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (45, 1, '19 MI', 'NINETEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (46, 1, '19 MILE', 'NINETEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (47, 1, '19MI', 'NINETEEN MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (48, 1, '1ER', 'PREMIERE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (49, 1, '1ER', '1', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (50, 1, '1MI', 'ONE MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (51, 1, '1RE', 'PREMIERE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (52, 1, '1RE', '1', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (53, 1, '1ST', '1', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (54, 2, '1ST', '1ST', 15, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (55, 1, '2 MI', 'TWO MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (56, 1, '2 MILE', 'TWO MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (57, 1, '20 MI', 'TWENTY MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (58, 1, '20 MILE', 'TWENTY MILE', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (211, 1, 'AND', 'AND', 13, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2080, 2, 'ROUTE', 'RTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2082, 1, 'ROUTE NO', 'RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2083, 2, 'ROUTE NO', 'RTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2085, 2, 'ROUTE NUMBER', 'RTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2098, 1, 'RT', 'RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2099, 2, 'RT', 'RTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2100, 1, 'RT NO', 'RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2101, 2, 'RT NO', 'RTE', 8, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2102, 1, 'RTE', 'RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2084, 1, 'ROUTE NUMBER', 'RTE', 6, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2069, 1, 'RN', 'RUN', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2479, 1, 'SVRD', 'SVC RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2152, 1, 'SERVICE RD', 'SVC RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2153, 1, 'SERVICE ROAD', 'SVC RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2478, 1, 'SVC RD', 'SVC RD', 2, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2340, 1, 'SPUR', 'SPUR', 3, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2349, 2, 'SQU', 'SQ', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2347, 2, 'SQR', 'SQ', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2345, 2, 'SQ', 'SQ', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2353, 2, 'SQURE', 'SQ', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2351, 2, 'SQUARE', 'SQ', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2418, 2, 'STN', 'STA', 24, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2935, 2, 'NORTHWEST', 'NW', 22, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2936, 2, 'NORTH', 'NORTH', 1, false);
INSERT INTO pagc_lex (id, seq, word, stdword, token, is_custom) VALUES (2937, 2, 'SOUTH', 'SOUTH', 1, false);

SELECT pg_catalog.setval('pagc_lex_id_seq', (SELECT greatest((SELECT MAX(id) FROM pagc_lex),50000)), true);

-- set default to false so all we input will be treated as no custom --
ALTER TABLE tiger.pagc_rules ALTER COLUMN is_custom SET DEFAULT false;
INSERT INTO pagc_rules (id, rule) VALUES (1, '1 -1 5 -1 2 7');
INSERT INTO pagc_rules (id, rule) VALUES (2, '1 3 -1 5 3 -1 2 7');
INSERT INTO pagc_rules (id, rule) VALUES (3, '1 22 -1 5 7 -1 2 7');
INSERT INTO pagc_rules (id, rule) VALUES (4, '1 22 3 -1 5 7 3 -1 2 7');
INSERT INTO pagc_rules (id, rule) VALUES (5, '1 2 -1 5 6 -1 2 13');
INSERT INTO pagc_rules (id, rule) VALUES (6, '1 2 3 -1 5 6 3 -1 2 13');
INSERT INTO pagc_rules (id, rule) VALUES (7, '1 2 22 -1 5 6 7 -1 2 13');
INSERT INTO pagc_rules (id, rule) VALUES (8, '1 2 22 3 -1 5 6 7 3 -1 2 13');
INSERT INTO pagc_rules (id, rule) VALUES (9, '18 -1 5 -1 2 2');
INSERT INTO pagc_rules (id, rule) VALUES (10, '18 3 -1 5 3 -1 2 2');
INSERT INTO pagc_rules (id, rule) VALUES (11, '18 22 -1 5 7 -1 2 2');
INSERT INTO pagc_rules (id, rule) VALUES (12, '18 22 3 -1 5 7 3 -1 2 2');
INSERT INTO pagc_rules (id, rule) VALUES (13, '18 2 -1 5 6 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (14, '18 2 3 -1 5 6 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (15, '18 2 22 -1 5 6 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (16, '18 2 22 3 -1 5 6 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (17, '2 -1 5 -1 2 2');
INSERT INTO pagc_rules (id, rule) VALUES (18, '2 3 -1 5 3 -1 2 2');
INSERT INTO pagc_rules (id, rule) VALUES (19, '2 22 -1 5 7 -1 2 2');
INSERT INTO pagc_rules (id, rule) VALUES (20, '2 22 3 -1 5 7 3 -1 2 2');
INSERT INTO pagc_rules (id, rule) VALUES (21, '2 2 -1 5 6 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (22, '2 2 3 -1 5 6 3 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (23, '2 2 22 -1 5 6 7 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (24, '2 2 22 3 -1 5 6 7 3 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (25, '22 -1 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (26, '22 3 -1 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (27, '22 22 -1 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (28, '22 22 3 -1 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (29, '22 2 -1 5 6 -1 2 8');
INSERT INTO pagc_rules (id, rule) VALUES (30, '22 2 3 -1 5 6 3 -1 2 8');
INSERT INTO pagc_rules (id, rule) VALUES (31, '22 2 22 -1 5 6 7 -1 2 8');
INSERT INTO pagc_rules (id, rule) VALUES (32, '22 2 22 3 -1 5 6 7 3 -1 2 8');
INSERT INTO pagc_rules (id, rule) VALUES (33, '22 1 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (34, '22 1 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (35, '22 1 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (36, '22 1 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (37, '22 1 2 -1 5 5 6 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (38, '22 1 2 3 -1 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (39, '22 1 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (40, '22 1 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (41, '1 22 -1 5 5 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (42, '1 22 3 -1 5 5 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (43, '1 22 22 -1 5 5 7 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (44, '1 22 22 3 -1 5 5 7 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (45, '1 22 2 -1 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (46, '1 22 2 3 -1 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (47, '1 22 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (48, '1 22 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (49, '1 2 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (50, '1 2 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (51, '1 2 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (52, '1 2 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (53, '1 2 2 -1 5 5 6 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (54, '1 2 2 3 -1 5 5 6 3 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (55, '1 2 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (56, '1 2 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (57, '2 1 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (58, '2 1 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (59, '2 1 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (60, '2 1 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (61, '2 1 2 -1 5 5 6 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (62, '2 1 2 3 -1 5 5 6 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (63, '2 1 2 22 -1 5 5 6 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (64, '2 1 2 22 3 -1 5 5 6 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (65, '15 2 -1 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (66, '15 2 3 -1 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (67, '15 2 22 -1 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (68, '15 2 22 3 -1 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (69, '16 0 2 -1 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (70, '16 0 2 3 -1 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (71, '24 2 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (72, '24 2 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (73, '24 2 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (74, '24 2 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (75, '24 2 2 -1 5 5 6 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (76, '24 2 2 3 -1 5 5 6 3 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (77, '24 2 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (78, '24 2 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (79, '0 22 -1 5 5 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (80, '0 22 3 -1 5 5 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (81, '0 22 22 -1 5 5 7 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (82, '0 22 22 3 -1 5 5 7 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (83, '0 22 2 -1 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (84, '0 22 2 3 -1 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (85, '0 22 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (86, '0 22 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (87, '2 24 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (88, '2 24 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (89, '2 24 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (90, '2 24 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (91, '2 24 2 -1 5 5 6 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (92, '2 24 2 3 -1 5 5 6 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (93, '2 24 2 22 -1 5 5 6 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (94, '2 24 2 22 3 -1 5 5 6 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (95, '2 22 -1 5 5 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (96, '2 22 3 -1 5 5 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (97, '2 22 22 -1 5 5 7 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (98, '2 22 22 3 -1 5 5 7 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (99, '2 22 2 -1 5 5 6 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (100, '2 22 2 3 -1 5 5 6 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (101, '2 22 2 22 -1 5 5 6 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (102, '2 22 2 22 3 -1 5 5 6 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (103, '2 0 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (104, '2 0 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (105, '2 0 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (106, '2 0 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (107, '2 0 2 -1 5 5 6 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (108, '2 0 2 3 -1 5 5 6 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (109, '2 0 2 22 -1 5 5 6 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (110, '2 0 2 22 3 -1 5 5 6 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (111, '2 18 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (112, '2 18 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (113, '2 18 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (114, '2 18 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (115, '2 18 2 -1 5 5 6 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (116, '2 18 2 3 -1 5 5 6 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (117, '2 18 2 22 -1 5 5 6 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (118, '2 18 2 22 3 -1 5 5 6 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (119, '2 2 -1 5 5 -1 2 3');
INSERT INTO pagc_rules (id, rule) VALUES (120, '2 2 3 -1 5 5 3 -1 2 3');
INSERT INTO pagc_rules (id, rule) VALUES (121, '2 2 22 -1 5 5 7 -1 2 3');
INSERT INTO pagc_rules (id, rule) VALUES (122, '2 2 22 3 -1 5 5 7 3 -1 2 3');
INSERT INTO pagc_rules (id, rule) VALUES (123, '2 2 2 -1 5 5 6 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (124, '2 2 2 3 -1 5 5 6 3 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (125, '2 2 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (126, '2 2 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (127, '18 2 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (128, '18 2 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (129, '18 2 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (130, '18 2 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (131, '18 2 2 -1 5 5 6 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (132, '18 2 2 3 -1 5 5 6 3 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (133, '18 2 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (134, '18 2 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (135, '1 18 2 -1 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (136, '1 18 2 3 -1 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (137, '1 18 2 22 -1 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (138, '1 18 2 22 3 -1 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (139, '1 18 2 2 -1 5 5 5 6 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (140, '1 18 2 2 3 -1 5 5 5 6 3 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (141, '1 18 2 2 22 -1 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (142, '1 18 2 2 22 3 -1 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (143, '0 -1 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (144, '0 3 -1 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (145, '0 22 -1 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (146, '0 22 3 -1 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (147, '0 2 -1 5 6 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (148, '0 2 3 -1 5 6 3 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (149, '0 2 22 -1 5 6 7 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (150, '0 2 22 3 -1 5 6 7 3 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (151, '0 18 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (152, '0 18 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (153, '0 18 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (154, '0 18 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (155, '0 18 2 -1 5 5 6 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (156, '0 18 2 3 -1 5 5 6 3 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (157, '0 18 2 22 -1 5 5 6 7 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (158, '0 18 2 22 3 -1 5 5 6 7 3 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (159, '0 1 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (160, '0 1 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (161, '0 1 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (162, '0 1 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (163, '0 1 2 -1 5 5 6 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (164, '0 1 2 3 -1 5 5 6 3 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (165, '0 1 2 22 -1 5 5 6 7 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (166, '0 1 2 22 3 -1 5 5 6 7 3 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (167, '1 2 2 -1 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (168, '1 2 2 3 -1 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (169, '1 2 2 22 -1 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (170, '1 2 2 22 3 -1 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (171, '1 2 2 2 -1 5 5 5 6 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (172, '1 2 2 2 3 -1 5 5 5 6 3 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (173, '1 2 2 2 22 -1 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (174, '1 2 2 2 22 3 -1 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (175, '22 2 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (176, '22 2 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (177, '22 2 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (178, '22 2 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (179, '22 2 2 -1 5 5 6 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (180, '22 2 2 3 -1 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (181, '22 2 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (182, '22 2 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (183, '14 -1 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (184, '14 3 -1 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (185, '14 22 -1 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (186, '14 22 3 -1 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (187, '14 2 -1 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (188, '14 2 3 -1 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (189, '14 2 22 -1 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (190, '14 2 22 3 -1 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (191, '15 1 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (192, '15 1 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (193, '15 1 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (194, '15 1 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (195, '15 1 2 -1 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (196, '15 1 2 3 -1 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (197, '15 1 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (198, '15 1 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (199, '24 -1 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (200, '24 3 -1 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (201, '24 22 -1 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (202, '24 22 3 -1 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (203, '24 2 -1 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (204, '24 2 3 -1 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (205, '24 2 22 -1 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (206, '24 2 22 3 -1 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (207, '24 24 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (208, '24 24 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (209, '24 24 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (210, '24 24 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (211, '24 24 2 -1 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (212, '24 24 2 3 -1 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (213, '24 24 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (214, '24 24 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (215, '24 1 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (216, '24 1 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (217, '24 1 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (218, '24 1 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (219, '24 1 2 -1 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (220, '24 1 2 3 -1 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (221, '24 1 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (222, '24 1 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (223, '25 -1 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (224, '25 3 -1 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (225, '25 22 -1 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (226, '25 22 3 -1 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (227, '25 2 -1 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (228, '25 2 3 -1 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (229, '25 2 22 -1 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (230, '25 2 22 3 -1 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (231, '23 -1 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (232, '23 3 -1 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (233, '23 22 -1 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (234, '23 22 3 -1 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (235, '23 2 -1 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (236, '23 2 3 -1 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (237, '23 2 22 -1 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (238, '23 2 22 3 -1 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (239, '0 13 0 -1 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (240, '0 13 0 3 -1 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (241, '0 13 0 22 -1 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (242, '0 13 0 22 3 -1 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (243, '0 13 0 2 -1 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (244, '0 13 0 2 3 -1 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (245, '0 13 0 2 22 -1 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (246, '0 13 0 2 22 3 -1 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (247, '0 25 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (248, '0 25 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (249, '0 25 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (250, '0 25 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (251, '0 25 2 -1 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (252, '0 25 2 3 -1 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (253, '0 25 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (254, '0 25 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (255, '11 -1 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (256, '11 3 -1 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (257, '11 22 -1 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (258, '11 22 3 -1 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (259, '11 2 -1 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (260, '11 2 3 -1 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (261, '11 2 22 -1 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (262, '11 2 22 3 -1 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (263, '3 0 -1 3 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (264, '3 0 3 -1 3 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (265, '3 0 22 -1 3 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (266, '3 0 22 3 -1 3 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (267, '3 0 2 -1 3 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (268, '3 0 2 3 -1 3 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (269, '3 0 2 22 -1 3 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (270, '3 0 2 22 3 -1 3 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (271, '3 1 -1 3 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (272, '3 1 3 -1 3 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (273, '3 1 22 -1 3 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (274, '3 1 22 3 -1 3 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (275, '3 1 2 -1 3 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (276, '3 1 2 3 -1 3 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (277, '3 1 2 22 -1 3 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (278, '3 1 2 22 3 -1 3 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (279, '18 13 18 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (280, '18 13 18 3 -1 5 5 3 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (281, '18 13 18 22 -1 5 5 3 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (282, '18 13 18 22 3 -1 5 5 3 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (283, '18 13 18 2 -1 5 5 3 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (284, '18 13 18 2 3 -1 5 5 3 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (285, '18 13 18 2 22 -1 5 5 3 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (286, '18 13 18 2 22 3 -1 5 5 3 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (287, '18 0 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (288, '18 0 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (289, '18 0 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (290, '18 0 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (291, '18 0 2 -1 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (292, '18 0 2 3 -1 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (293, '18 0 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (294, '18 0 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (295, '18 18 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (296, '18 18 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (297, '18 18 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (298, '18 18 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (299, '18 18 2 -1 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (300, '18 18 2 3 -1 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (301, '18 18 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (302, '18 18 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (303, '18 18 18 -1 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (304, '18 18 18 3 -1 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (305, '18 18 18 22 -1 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (306, '18 18 18 22 3 -1 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (307, '18 18 18 2 -1 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (308, '18 18 18 2 3 -1 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (309, '18 18 18 2 22 -1 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (310, '18 18 18 2 22 3 -1 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (311, '18 18 1 -1 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (312, '18 18 1 3 -1 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (313, '18 18 1 22 -1 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (314, '18 18 1 22 3 -1 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (315, '18 18 1 2 -1 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (316, '18 18 1 2 3 -1 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (317, '18 18 1 2 22 -1 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (318, '18 18 1 2 22 3 -1 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (319, '18 1 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (320, '18 1 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (321, '18 1 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (322, '18 1 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (323, '18 1 2 -1 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (324, '18 1 2 3 -1 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (325, '18 1 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (326, '18 1 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (327, '5 -1 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (328, '5 3 -1 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (329, '5 22 -1 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (330, '5 22 3 -1 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (331, '5 2 -1 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (332, '5 2 3 -1 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (333, '5 2 22 -1 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (334, '5 2 22 3 -1 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (335, '21 -1 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (336, '21 3 -1 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (337, '21 22 -1 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (338, '21 22 3 -1 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (339, '21 2 -1 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (340, '21 2 3 -1 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (341, '21 2 22 -1 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (342, '21 2 22 3 -1 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (343, '1 13 1 -1 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (344, '1 13 1 3 -1 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (345, '1 13 1 22 -1 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (346, '1 13 1 22 3 -1 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (347, '1 13 1 2 -1 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (348, '1 13 1 2 3 -1 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (349, '1 13 1 2 22 -1 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (350, '1 13 1 2 22 3 -1 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (351, '1 24 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (352, '1 24 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (353, '1 24 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (354, '1 24 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (355, '1 24 2 -1 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (356, '1 24 2 3 -1 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (357, '1 24 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (358, '1 24 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (359, '1 24 24 -1 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (360, '1 24 24 3 -1 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (361, '1 24 24 22 -1 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (362, '1 24 24 22 3 -1 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (363, '1 24 24 2 -1 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (364, '1 24 24 2 3 -1 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (365, '1 24 24 2 22 -1 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (366, '1 24 24 2 22 3 -1 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (367, '1 24 1 -1 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (368, '1 24 1 3 -1 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (369, '1 24 1 22 -1 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (370, '1 24 1 22 3 -1 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (371, '1 24 1 2 -1 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (372, '1 24 1 2 3 -1 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (373, '1 24 1 2 22 -1 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (374, '1 24 1 2 22 3 -1 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (375, '1 15 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (376, '1 15 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (377, '1 15 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (378, '1 15 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (379, '1 15 2 -1 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (380, '1 15 2 3 -1 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (381, '1 15 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (382, '1 15 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (383, '1 22 1 -1 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (384, '1 22 1 3 -1 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (385, '1 22 1 22 -1 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (386, '1 22 1 22 3 -1 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (387, '1 22 1 2 -1 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (388, '1 22 1 2 3 -1 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (389, '1 22 1 2 22 -1 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (390, '1 22 1 2 22 3 -1 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (391, '1 25 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (392, '1 25 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (393, '1 25 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (394, '1 25 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (395, '1 25 2 -1 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (396, '1 25 2 3 -1 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (397, '1 25 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (398, '1 25 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (399, '1 0 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (400, '1 0 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (401, '1 0 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (402, '1 0 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (403, '1 0 2 -1 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (404, '1 0 2 3 -1 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (405, '1 0 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (406, '1 0 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (407, '1 3 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (408, '1 3 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (409, '1 3 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (410, '1 3 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (411, '1 3 2 -1 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (412, '1 3 2 3 -1 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (413, '1 3 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (414, '1 3 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (415, '1 18 -1 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (416, '1 18 3 -1 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (417, '1 18 22 -1 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (418, '1 18 22 3 -1 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (419, '1 18 2 -1 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (420, '1 18 2 3 -1 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (421, '1 18 2 22 -1 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (422, '1 18 2 22 3 -1 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (423, '1 18 18 1 -1 5 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (424, '1 18 18 1 3 -1 5 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (425, '1 18 18 1 22 -1 5 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (426, '1 18 18 1 22 3 -1 5 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (427, '1 18 18 1 2 -1 5 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (428, '1 18 18 1 2 3 -1 5 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (429, '1 18 18 1 2 22 -1 5 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (430, '1 18 18 1 2 22 3 -1 5 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (431, '1 18 1 -1 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (432, '1 18 1 3 -1 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (433, '1 18 1 22 -1 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (434, '1 18 1 22 3 -1 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (435, '1 18 1 2 -1 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (436, '1 18 1 2 3 -1 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (437, '1 18 1 2 22 -1 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (438, '1 18 1 2 22 3 -1 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (439, '1 2 0 -1 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (440, '1 2 0 3 -1 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (441, '1 2 0 22 -1 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (442, '1 2 0 22 3 -1 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (443, '1 2 0 2 -1 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (444, '1 2 0 2 3 -1 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (445, '1 2 0 2 22 -1 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (446, '1 2 0 2 22 3 -1 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (447, '1 2 1 -1 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (448, '1 2 1 3 -1 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (449, '1 2 1 22 -1 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (450, '1 2 1 22 3 -1 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (451, '1 2 1 2 -1 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (452, '1 2 1 2 3 -1 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (453, '1 2 1 2 22 -1 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (454, '1 2 1 2 22 3 -1 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (455, '16 -1 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (456, '16 3 -1 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (457, '16 22 -1 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (458, '16 22 3 -1 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (459, '16 2 -1 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (460, '16 2 3 -1 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (461, '16 2 22 -1 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (462, '16 2 22 3 -1 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (463, '2 1 -1 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (464, '2 1 3 -1 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (465, '2 1 22 -1 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (466, '2 1 22 3 -1 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (467, '2 18 -1 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (468, '2 18 3 -1 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (469, '2 18 22 -1 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (470, '2 18 22 3 -1 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (471, '2 2 -1 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (472, '2 2 3 -1 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (473, '2 2 22 -1 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (474, '2 2 22 3 -1 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (475, '2 22 -1 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (476, '2 22 3 -1 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (477, '2 22 22 -1 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (478, '2 22 22 3 -1 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (479, '2 22 1 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (480, '2 22 1 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (481, '2 22 1 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (482, '2 22 1 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (483, '2 1 22 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (484, '2 1 22 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (485, '2 1 22 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (486, '2 1 22 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (487, '2 1 2 -1 4 5 5 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (488, '2 1 2 3 -1 4 5 5 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (489, '2 1 2 22 -1 4 5 5 7 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (490, '2 1 2 22 3 -1 4 5 5 7 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (491, '2 2 1 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (492, '2 2 1 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (493, '2 2 1 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (494, '2 2 1 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (495, '2 24 2 -1 4 5 5 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (496, '2 24 2 3 -1 4 5 5 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (497, '2 24 2 22 -1 4 5 5 7 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (498, '2 24 2 22 3 -1 4 5 5 7 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (499, '2 0 22 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (500, '2 0 22 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (501, '2 0 22 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (502, '2 0 22 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (503, '2 2 24 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (504, '2 2 24 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (505, '2 2 24 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (506, '2 2 24 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (507, '2 2 22 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (508, '2 2 22 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (509, '2 2 22 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (510, '2 2 22 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (511, '2 2 0 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (512, '2 2 0 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (513, '2 2 0 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (514, '2 2 0 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (515, '2 2 18 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (516, '2 2 18 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (517, '2 2 18 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (518, '2 2 18 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (519, '2 2 2 -1 4 5 5 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (520, '2 2 2 3 -1 4 5 5 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (521, '2 2 2 22 -1 4 5 5 7 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (522, '2 2 2 22 3 -1 4 5 5 7 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (523, '2 18 2 -1 4 5 5 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (524, '2 18 2 3 -1 4 5 5 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (525, '2 18 2 22 -1 4 5 5 7 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (526, '2 18 2 22 3 -1 4 5 5 7 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (527, '2 1 18 2 -1 4 5 5 5 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (528, '2 1 18 2 3 -1 4 5 5 5 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (529, '2 1 18 2 22 -1 4 5 5 5 7 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (530, '2 1 18 2 22 3 -1 4 5 5 5 7 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (531, '2 0 -1 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (532, '2 0 3 -1 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (533, '2 0 22 -1 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (534, '2 0 22 3 -1 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (535, '2 0 18 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (536, '2 0 18 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (537, '2 0 18 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (538, '2 0 18 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (539, '2 0 1 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (540, '2 0 1 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (541, '2 0 1 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (542, '2 0 1 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (543, '2 1 2 2 -1 4 5 5 5 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (544, '2 1 2 2 3 -1 4 5 5 5 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (545, '2 1 2 2 22 -1 4 5 5 5 7 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (546, '2 1 2 2 22 3 -1 4 5 5 5 7 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (547, '2 22 2 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (548, '2 22 2 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (549, '2 22 2 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (550, '2 22 2 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (551, '2 14 -1 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (552, '2 14 3 -1 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (553, '2 14 22 -1 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (554, '2 14 22 3 -1 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (555, '2 15 1 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (556, '2 15 1 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (557, '2 15 1 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (558, '2 15 1 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (559, '2 24 -1 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (560, '2 24 3 -1 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (561, '2 24 22 -1 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (562, '2 24 22 3 -1 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (563, '2 24 24 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (564, '2 24 24 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (565, '2 24 24 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (566, '2 24 24 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (567, '2 24 1 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (568, '2 24 1 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (569, '2 24 1 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (570, '2 24 1 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (571, '2 25 -1 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (572, '2 25 3 -1 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (573, '2 25 22 -1 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (574, '2 25 22 3 -1 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (575, '2 23 -1 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (576, '2 23 3 -1 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (577, '2 23 22 -1 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (578, '2 23 22 3 -1 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (579, '2 0 13 0 -1 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (580, '2 0 13 0 3 -1 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (581, '2 0 13 0 22 -1 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (582, '2 0 13 0 22 3 -1 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (583, '2 0 25 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (584, '2 0 25 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (585, '2 0 25 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (586, '2 0 25 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (587, '2 11 -1 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (588, '2 11 3 -1 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (589, '2 11 22 -1 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (590, '2 11 22 3 -1 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (591, '2 3 0 -1 4 3 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (592, '2 3 0 3 -1 4 3 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (593, '2 3 0 22 -1 4 3 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (594, '2 3 0 22 3 -1 4 3 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (595, '2 3 1 -1 4 3 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (596, '2 3 1 3 -1 4 3 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (597, '2 3 1 22 -1 4 3 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (598, '2 3 1 22 3 -1 4 3 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (599, '2 18 13 18 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (600, '2 18 13 18 3 -1 4 5 5 3 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (601, '2 18 13 18 22 -1 4 5 5 3 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (602, '2 18 13 18 22 3 -1 4 5 5 3 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (603, '2 18 0 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (604, '2 18 0 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (605, '2 18 0 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (606, '2 18 0 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (607, '2 18 18 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (608, '2 18 18 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (609, '2 18 18 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (610, '2 18 18 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (611, '2 18 18 18 -1 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (612, '2 18 18 18 3 -1 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (613, '2 18 18 18 22 -1 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (614, '2 18 18 18 22 3 -1 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (615, '2 18 18 1 -1 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (616, '2 18 18 1 3 -1 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (617, '2 18 18 1 22 -1 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (618, '2 18 18 1 22 3 -1 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (619, '2 18 1 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (620, '2 18 1 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (621, '2 18 1 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (622, '2 18 1 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (623, '2 5 -1 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (624, '2 5 3 -1 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (625, '2 5 22 -1 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (626, '2 5 22 3 -1 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (627, '2 21 -1 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (628, '2 21 3 -1 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (629, '2 21 22 -1 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (630, '2 21 22 3 -1 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (631, '2 1 13 1 -1 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (632, '2 1 13 1 3 -1 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (633, '2 1 13 1 22 -1 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (634, '2 1 13 1 22 3 -1 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (635, '2 1 24 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (636, '2 1 24 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (637, '2 1 24 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (638, '2 1 24 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (639, '2 1 24 24 -1 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (640, '2 1 24 24 3 -1 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (641, '2 1 24 24 22 -1 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (642, '2 1 24 24 22 3 -1 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (643, '2 1 24 1 -1 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (644, '2 1 24 1 3 -1 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (645, '2 1 24 1 22 -1 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (646, '2 1 24 1 22 3 -1 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (647, '2 1 15 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (648, '2 1 15 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (649, '2 1 15 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (650, '2 1 15 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (651, '2 1 22 1 -1 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (652, '2 1 22 1 3 -1 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (653, '2 1 22 1 22 -1 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (654, '2 1 22 1 22 3 -1 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (655, '2 1 25 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (656, '2 1 25 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (657, '2 1 25 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (658, '2 1 25 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (659, '2 1 0 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (660, '2 1 0 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (661, '2 1 0 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (662, '2 1 0 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (663, '2 1 3 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (664, '2 1 3 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (665, '2 1 3 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (666, '2 1 3 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (667, '2 1 18 -1 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (668, '2 1 18 3 -1 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (669, '2 1 18 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (670, '2 1 18 22 3 -1 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (671, '2 1 18 18 1 -1 4 5 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (672, '2 1 18 18 1 3 -1 4 5 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (673, '2 1 18 18 1 22 -1 4 5 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (674, '2 1 18 18 1 22 3 -1 4 5 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (675, '2 1 18 1 -1 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (676, '2 1 18 1 3 -1 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (677, '2 1 18 1 22 -1 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (678, '2 1 18 1 22 3 -1 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (679, '2 1 2 0 -1 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (680, '2 1 2 0 3 -1 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (681, '2 1 2 0 22 -1 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (682, '2 1 2 0 22 3 -1 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (683, '2 1 2 1 -1 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (684, '2 1 2 1 3 -1 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (685, '2 1 2 1 22 -1 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (686, '2 1 2 1 22 3 -1 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (687, '2 16 -1 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (688, '2 16 3 -1 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (689, '2 16 22 -1 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (690, '2 16 22 3 -1 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (691, '22 1 -1 2 5 -1 2 7');
INSERT INTO pagc_rules (id, rule) VALUES (692, '22 1 3 -1 2 5 3 -1 2 7');
INSERT INTO pagc_rules (id, rule) VALUES (693, '22 1 22 -1 2 5 7 -1 2 7');
INSERT INTO pagc_rules (id, rule) VALUES (694, '22 1 22 3 -1 2 5 7 3 -1 2 7');
INSERT INTO pagc_rules (id, rule) VALUES (695, '22 1 2 -1 2 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (696, '22 1 2 3 -1 2 5 6 3 -1 2 13');
INSERT INTO pagc_rules (id, rule) VALUES (697, '22 1 2 22 -1 2 5 6 7 -1 2 13');
INSERT INTO pagc_rules (id, rule) VALUES (698, '22 1 2 22 3 -1 2 5 6 7 3 -1 2 13');
INSERT INTO pagc_rules (id, rule) VALUES (699, '22 18 -1 2 5 -1 2 2');
INSERT INTO pagc_rules (id, rule) VALUES (700, '22 18 3 -1 2 5 3 -1 2 2');
INSERT INTO pagc_rules (id, rule) VALUES (701, '22 18 22 -1 2 5 7 -1 2 2');
INSERT INTO pagc_rules (id, rule) VALUES (702, '22 18 22 3 -1 2 5 7 3 -1 2 2');
INSERT INTO pagc_rules (id, rule) VALUES (703, '22 18 2 -1 2 5 6 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (704, '22 18 2 3 -1 2 5 6 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (705, '22 18 2 22 -1 2 5 6 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (706, '22 18 2 22 3 -1 2 5 6 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (707, '22 2 -1 2 5 -1 2 2');
INSERT INTO pagc_rules (id, rule) VALUES (708, '22 2 3 -1 2 5 3 -1 2 2');
INSERT INTO pagc_rules (id, rule) VALUES (709, '22 2 22 -1 2 5 7 -1 2 2');
INSERT INTO pagc_rules (id, rule) VALUES (710, '22 2 22 3 -1 2 5 7 3 -1 2 2');
INSERT INTO pagc_rules (id, rule) VALUES (711, '22 2 2 -1 2 5 6 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (712, '22 2 2 3 -1 2 5 6 3 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (713, '22 2 2 22 -1 2 5 6 7 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (714, '22 2 2 22 3 -1 2 5 6 7 3 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (715, '22 22 -1 2 5 -1 2 7');
INSERT INTO pagc_rules (id, rule) VALUES (716, '22 22 3 -1 2 5 3 -1 2 7');
INSERT INTO pagc_rules (id, rule) VALUES (717, '22 22 22 -1 2 5 7 -1 2 7');
INSERT INTO pagc_rules (id, rule) VALUES (718, '22 22 22 3 -1 2 5 7 3 -1 2 7');
INSERT INTO pagc_rules (id, rule) VALUES (719, '22 22 2 -1 2 5 6 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (720, '22 22 2 3 -1 2 5 6 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (721, '22 22 2 22 -1 2 5 6 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (722, '22 22 2 22 3 -1 2 5 6 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (723, '22 22 1 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (724, '22 22 1 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (725, '22 22 1 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (726, '22 22 1 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (727, '22 22 1 2 -1 2 5 5 6 -1 2 8');
INSERT INTO pagc_rules (id, rule) VALUES (728, '22 22 1 2 3 -1 2 5 5 6 3 -1 2 8');
INSERT INTO pagc_rules (id, rule) VALUES (729, '22 22 1 2 22 -1 2 5 5 6 7 -1 2 8');
INSERT INTO pagc_rules (id, rule) VALUES (730, '22 22 1 2 22 3 -1 2 5 5 6 7 3 -1 2 8');
INSERT INTO pagc_rules (id, rule) VALUES (731, '22 1 22 -1 2 5 5 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (732, '22 1 22 3 -1 2 5 5 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (733, '22 1 22 22 -1 2 5 5 7 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (734, '22 1 22 22 3 -1 2 5 5 7 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (735, '22 1 22 2 -1 2 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (736, '22 1 22 2 3 -1 2 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (737, '22 1 22 2 22 -1 2 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (738, '22 1 22 2 22 3 -1 2 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (739, '22 1 2 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (740, '22 1 2 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (741, '22 1 2 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (742, '22 1 2 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (743, '22 1 2 2 -1 2 5 5 6 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (744, '22 1 2 2 3 -1 2 5 5 6 3 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (745, '22 1 2 2 22 -1 2 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (746, '22 1 2 2 22 3 -1 2 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (747, '22 2 1 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (748, '22 2 1 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (749, '22 2 1 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (750, '22 2 1 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (751, '22 2 1 2 -1 2 5 5 6 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (752, '22 2 1 2 3 -1 2 5 5 6 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (753, '22 2 1 2 22 -1 2 5 5 6 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (754, '22 2 1 2 22 3 -1 2 5 5 6 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (755, '22 15 2 -1 2 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (756, '22 15 2 3 -1 2 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (757, '22 15 2 22 -1 2 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (758, '22 15 2 22 3 -1 2 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (759, '22 16 0 2 -1 2 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (760, '22 16 0 2 3 -1 2 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (761, '22 24 2 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (762, '22 24 2 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (763, '22 24 2 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (764, '22 24 2 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (765, '22 24 2 2 -1 2 5 5 6 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (766, '22 24 2 2 3 -1 2 5 5 6 3 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (767, '22 24 2 2 22 -1 2 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (768, '22 24 2 2 22 3 -1 2 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (769, '22 0 22 -1 2 5 5 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (770, '22 0 22 3 -1 2 5 5 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (771, '22 0 22 22 -1 2 5 5 7 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (772, '22 0 22 22 3 -1 2 5 5 7 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (773, '22 0 22 2 -1 2 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (774, '22 0 22 2 3 -1 2 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (775, '22 0 22 2 22 -1 2 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (776, '22 0 22 2 22 3 -1 2 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (777, '22 2 24 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (778, '22 2 24 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (779, '22 2 24 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (780, '22 2 24 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (781, '22 2 24 2 -1 2 5 5 6 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (782, '22 2 24 2 3 -1 2 5 5 6 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (783, '22 2 24 2 22 -1 2 5 5 6 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (784, '22 2 24 2 22 3 -1 2 5 5 6 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (785, '22 2 22 -1 2 5 5 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (786, '22 2 22 3 -1 2 5 5 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (787, '22 2 22 22 -1 2 5 5 7 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (788, '22 2 22 22 3 -1 2 5 5 7 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (789, '22 2 22 2 -1 2 5 5 6 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (790, '22 2 22 2 3 -1 2 5 5 6 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (791, '22 2 22 2 22 -1 2 5 5 6 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (792, '22 2 22 2 22 3 -1 2 5 5 6 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (793, '22 2 0 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (794, '22 2 0 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (795, '22 2 0 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (796, '22 2 0 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (797, '22 2 0 2 -1 2 5 5 6 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (798, '22 2 0 2 3 -1 2 5 5 6 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (799, '22 2 0 2 22 -1 2 5 5 6 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (800, '22 2 0 2 22 3 -1 2 5 5 6 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (801, '22 2 18 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (802, '22 2 18 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (803, '22 2 18 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (804, '22 2 18 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (805, '22 2 18 2 -1 2 5 5 6 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (806, '22 2 18 2 3 -1 2 5 5 6 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (807, '22 2 18 2 22 -1 2 5 5 6 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (808, '22 2 18 2 22 3 -1 2 5 5 6 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (809, '22 2 2 -1 2 5 5 -1 2 3');
INSERT INTO pagc_rules (id, rule) VALUES (810, '22 2 2 3 -1 2 5 5 3 -1 2 3');
INSERT INTO pagc_rules (id, rule) VALUES (811, '22 2 2 22 -1 2 5 5 7 -1 2 3');
INSERT INTO pagc_rules (id, rule) VALUES (812, '22 2 2 22 3 -1 2 5 5 7 3 -1 2 3');
INSERT INTO pagc_rules (id, rule) VALUES (813, '22 2 2 2 -1 2 5 5 6 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (814, '22 2 2 2 3 -1 2 5 5 6 3 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (815, '22 2 2 2 22 -1 2 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (816, '22 2 2 2 22 3 -1 2 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (817, '22 18 2 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (818, '22 18 2 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (819, '22 18 2 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (820, '22 18 2 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (821, '22 18 2 2 -1 2 5 5 6 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (822, '22 18 2 2 3 -1 2 5 5 6 3 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (823, '22 18 2 2 22 -1 2 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (824, '22 18 2 2 22 3 -1 2 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (825, '22 1 18 2 -1 2 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (826, '22 1 18 2 3 -1 2 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (827, '22 1 18 2 22 -1 2 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (828, '22 1 18 2 22 3 -1 2 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (829, '22 1 18 2 2 -1 2 5 5 5 6 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (830, '22 1 18 2 2 3 -1 2 5 5 5 6 3 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (831, '22 1 18 2 2 22 -1 2 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (832, '22 1 18 2 2 22 3 -1 2 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (833, '22 0 -1 2 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (834, '22 0 3 -1 2 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (835, '22 0 22 -1 2 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (836, '22 0 22 3 -1 2 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (837, '22 0 2 -1 2 5 6 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (838, '22 0 2 3 -1 2 5 6 3 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (839, '22 0 2 22 -1 2 5 6 7 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (840, '22 0 2 22 3 -1 2 5 6 7 3 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (841, '22 0 18 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (842, '22 0 18 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (843, '22 0 18 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (844, '22 0 18 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (845, '22 0 18 2 -1 2 5 5 6 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (846, '22 0 18 2 3 -1 2 5 5 6 3 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (847, '22 0 18 2 22 -1 2 5 5 6 7 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (848, '22 0 18 2 22 3 -1 2 5 5 6 7 3 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (849, '22 0 1 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (850, '22 0 1 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (851, '22 0 1 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (852, '22 0 1 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (853, '22 0 1 2 -1 2 5 5 6 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (854, '22 0 1 2 3 -1 2 5 5 6 3 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (855, '22 0 1 2 22 -1 2 5 5 6 7 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (856, '22 0 1 2 22 3 -1 2 5 5 6 7 3 -1 2 10');
INSERT INTO pagc_rules (id, rule) VALUES (857, '22 1 2 2 -1 2 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (858, '22 1 2 2 3 -1 2 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (859, '22 1 2 2 22 -1 2 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (860, '22 1 2 2 22 3 -1 2 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (861, '22 1 2 2 2 -1 2 5 5 5 6 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (862, '22 1 2 2 2 3 -1 2 5 5 5 6 3 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (863, '22 1 2 2 2 22 -1 2 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (864, '22 1 2 2 2 22 3 -1 2 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (865, '22 22 2 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (866, '22 22 2 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (867, '22 22 2 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (868, '22 22 2 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (869, '22 22 2 2 -1 2 5 5 6 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (870, '22 22 2 2 3 -1 2 5 5 6 3 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (871, '22 22 2 2 22 -1 2 5 5 6 7 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (872, '22 22 2 2 22 3 -1 2 5 5 6 7 3 -1 2 5');
INSERT INTO pagc_rules (id, rule) VALUES (873, '22 14 -1 2 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (874, '22 14 3 -1 2 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (875, '22 14 22 -1 2 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (876, '22 14 22 3 -1 2 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (877, '22 14 2 -1 2 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (878, '22 14 2 3 -1 2 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (879, '22 14 2 22 -1 2 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (880, '22 14 2 22 3 -1 2 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (881, '22 15 1 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (882, '22 15 1 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (883, '22 15 1 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (884, '22 15 1 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (885, '22 15 1 2 -1 2 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (886, '22 15 1 2 3 -1 2 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (887, '22 15 1 2 22 -1 2 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (888, '22 15 1 2 22 3 -1 2 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (889, '22 24 -1 2 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (890, '22 24 3 -1 2 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (891, '22 24 22 -1 2 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (892, '22 24 22 3 -1 2 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (893, '22 24 2 -1 2 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (894, '22 24 2 3 -1 2 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (895, '22 24 2 22 -1 2 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (896, '22 24 2 22 3 -1 2 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (897, '22 24 24 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (898, '22 24 24 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (899, '22 24 24 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (900, '22 24 24 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (901, '22 24 24 2 -1 2 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (902, '22 24 24 2 3 -1 2 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (903, '22 24 24 2 22 -1 2 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (904, '22 24 24 2 22 3 -1 2 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (905, '22 24 1 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (906, '22 24 1 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (907, '22 24 1 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (908, '22 24 1 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (909, '22 24 1 2 -1 2 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (910, '22 24 1 2 3 -1 2 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (911, '22 24 1 2 22 -1 2 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (912, '22 24 1 2 22 3 -1 2 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (913, '22 25 -1 2 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (914, '22 25 3 -1 2 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (915, '22 25 22 -1 2 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (916, '22 25 22 3 -1 2 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (917, '22 25 2 -1 2 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (918, '22 25 2 3 -1 2 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (919, '22 25 2 22 -1 2 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (920, '22 25 2 22 3 -1 2 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (921, '22 23 -1 2 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (922, '22 23 3 -1 2 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (923, '22 23 22 -1 2 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (924, '22 23 22 3 -1 2 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (925, '22 23 2 -1 2 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (926, '22 23 2 3 -1 2 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (927, '22 23 2 22 -1 2 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (928, '22 23 2 22 3 -1 2 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (929, '22 0 13 0 -1 2 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (930, '22 0 13 0 3 -1 2 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (931, '22 0 13 0 22 -1 2 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (932, '22 0 13 0 22 3 -1 2 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (933, '22 0 13 0 2 -1 2 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (934, '22 0 13 0 2 3 -1 2 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (935, '22 0 13 0 2 22 -1 2 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (936, '22 0 13 0 2 22 3 -1 2 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (937, '22 0 25 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (938, '22 0 25 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (939, '22 0 25 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (940, '22 0 25 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (941, '22 0 25 2 -1 2 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (942, '22 0 25 2 3 -1 2 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (943, '22 0 25 2 22 -1 2 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (944, '22 0 25 2 22 3 -1 2 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (945, '22 11 -1 2 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (946, '22 11 3 -1 2 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (947, '22 11 22 -1 2 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (948, '22 11 22 3 -1 2 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (949, '22 11 2 -1 2 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (950, '22 11 2 3 -1 2 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (951, '22 11 2 22 -1 2 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (952, '22 11 2 22 3 -1 2 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (953, '22 3 0 -1 2 3 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (954, '22 3 0 3 -1 2 3 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (955, '22 3 0 22 -1 2 3 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (956, '22 3 0 22 3 -1 2 3 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (957, '22 3 0 2 -1 2 3 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (958, '22 3 0 2 3 -1 2 3 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (959, '22 3 0 2 22 -1 2 3 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (960, '22 3 0 2 22 3 -1 2 3 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (961, '22 3 1 -1 2 3 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (962, '22 3 1 3 -1 2 3 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (963, '22 3 1 22 -1 2 3 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (964, '22 3 1 22 3 -1 2 3 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (965, '22 3 1 2 -1 2 3 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (966, '22 3 1 2 3 -1 2 3 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (967, '22 3 1 2 22 -1 2 3 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (968, '22 3 1 2 22 3 -1 2 3 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (969, '22 18 13 18 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (970, '22 18 13 18 3 -1 2 5 5 3 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (971, '22 18 13 18 22 -1 2 5 5 3 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (972, '22 18 13 18 22 3 -1 2 5 5 3 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (973, '22 18 13 18 2 -1 2 5 5 3 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (974, '22 18 13 18 2 3 -1 2 5 5 3 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (975, '22 18 13 18 2 22 -1 2 5 5 3 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (976, '22 18 13 18 2 22 3 -1 2 5 5 3 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (977, '22 18 0 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (978, '22 18 0 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (979, '22 18 0 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (980, '22 18 0 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (981, '22 18 0 2 -1 2 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (982, '22 18 0 2 3 -1 2 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (983, '22 18 0 2 22 -1 2 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (984, '22 18 0 2 22 3 -1 2 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (985, '22 18 18 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (986, '22 18 18 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (987, '22 18 18 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (988, '22 18 18 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (989, '22 18 18 2 -1 2 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (990, '22 18 18 2 3 -1 2 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (991, '22 18 18 2 22 -1 2 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (992, '22 18 18 2 22 3 -1 2 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (993, '22 18 18 18 -1 2 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (994, '22 18 18 18 3 -1 2 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (995, '22 18 18 18 22 -1 2 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (996, '22 18 18 18 22 3 -1 2 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (997, '22 18 18 18 2 -1 2 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (998, '22 18 18 18 2 3 -1 2 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (999, '22 18 18 18 2 22 -1 2 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1000, '22 18 18 18 2 22 3 -1 2 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1001, '22 18 18 1 -1 2 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1002, '22 18 18 1 3 -1 2 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1003, '22 18 18 1 22 -1 2 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1004, '22 18 18 1 22 3 -1 2 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1005, '22 18 18 1 2 -1 2 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1006, '22 18 18 1 2 3 -1 2 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1007, '22 18 18 1 2 22 -1 2 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1008, '22 18 18 1 2 22 3 -1 2 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1009, '22 18 1 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1010, '22 18 1 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1011, '22 18 1 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1012, '22 18 1 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1013, '22 18 1 2 -1 2 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1014, '22 18 1 2 3 -1 2 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1015, '22 18 1 2 22 -1 2 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1016, '22 18 1 2 22 3 -1 2 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1017, '22 5 -1 2 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1018, '22 5 3 -1 2 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1019, '22 5 22 -1 2 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1020, '22 5 22 3 -1 2 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1021, '22 5 2 -1 2 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1022, '22 5 2 3 -1 2 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1023, '22 5 2 22 -1 2 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1024, '22 5 2 22 3 -1 2 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1025, '22 21 -1 2 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1026, '22 21 3 -1 2 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1027, '22 21 22 -1 2 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1028, '22 21 22 3 -1 2 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1029, '22 21 2 -1 2 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1030, '22 21 2 3 -1 2 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1031, '22 21 2 22 -1 2 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1032, '22 21 2 22 3 -1 2 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1033, '22 1 13 1 -1 2 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1034, '22 1 13 1 3 -1 2 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1035, '22 1 13 1 22 -1 2 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1036, '22 1 13 1 22 3 -1 2 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1037, '22 1 13 1 2 -1 2 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1038, '22 1 13 1 2 3 -1 2 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1039, '22 1 13 1 2 22 -1 2 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1040, '22 1 13 1 2 22 3 -1 2 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1041, '22 1 24 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1042, '22 1 24 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1043, '22 1 24 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1044, '22 1 24 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1045, '22 1 24 2 -1 2 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1046, '22 1 24 2 3 -1 2 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1047, '22 1 24 2 22 -1 2 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1048, '22 1 24 2 22 3 -1 2 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1049, '22 1 24 24 -1 2 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1050, '22 1 24 24 3 -1 2 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1051, '22 1 24 24 22 -1 2 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1052, '22 1 24 24 22 3 -1 2 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1053, '22 1 24 24 2 -1 2 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1054, '22 1 24 24 2 3 -1 2 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1055, '22 1 24 24 2 22 -1 2 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1056, '22 1 24 24 2 22 3 -1 2 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1057, '22 1 24 1 -1 2 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1058, '22 1 24 1 3 -1 2 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1059, '22 1 24 1 22 -1 2 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1060, '22 1 24 1 22 3 -1 2 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1061, '22 1 24 1 2 -1 2 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1062, '22 1 24 1 2 3 -1 2 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1063, '22 1 24 1 2 22 -1 2 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1064, '22 1 24 1 2 22 3 -1 2 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1065, '22 1 15 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1066, '22 1 15 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1067, '22 1 15 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1068, '22 1 15 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1069, '22 1 15 2 -1 2 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1070, '22 1 15 2 3 -1 2 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1071, '22 1 15 2 22 -1 2 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1072, '22 1 15 2 22 3 -1 2 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1073, '22 1 22 1 -1 2 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1074, '22 1 22 1 3 -1 2 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1075, '22 1 22 1 22 -1 2 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1076, '22 1 22 1 22 3 -1 2 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1077, '22 1 22 1 2 -1 2 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1078, '22 1 22 1 2 3 -1 2 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1079, '22 1 22 1 2 22 -1 2 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1080, '22 1 22 1 2 22 3 -1 2 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1081, '22 1 25 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1082, '22 1 25 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1083, '22 1 25 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1084, '22 1 25 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1085, '22 1 25 2 -1 2 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1086, '22 1 25 2 3 -1 2 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1087, '22 1 25 2 22 -1 2 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1088, '22 1 25 2 22 3 -1 2 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1089, '22 1 0 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1090, '22 1 0 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1091, '22 1 0 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1092, '22 1 0 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1093, '22 1 0 2 -1 2 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1094, '22 1 0 2 3 -1 2 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1095, '22 1 0 2 22 -1 2 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1096, '22 1 0 2 22 3 -1 2 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1097, '22 1 3 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1098, '22 1 3 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1099, '22 1 3 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1100, '22 1 3 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1101, '22 1 3 2 -1 2 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1102, '22 1 3 2 3 -1 2 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1103, '22 1 3 2 22 -1 2 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1104, '22 1 3 2 22 3 -1 2 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1105, '22 1 18 -1 2 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1106, '22 1 18 3 -1 2 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1107, '22 1 18 22 -1 2 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1108, '22 1 18 22 3 -1 2 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1109, '22 1 18 2 -1 2 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1110, '22 1 18 2 3 -1 2 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1111, '22 1 18 2 22 -1 2 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1112, '22 1 18 2 22 3 -1 2 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1113, '22 1 18 18 1 -1 2 5 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1114, '22 1 18 18 1 3 -1 2 5 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1115, '22 1 18 18 1 22 -1 2 5 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1116, '22 1 18 18 1 22 3 -1 2 5 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1117, '22 1 18 18 1 2 -1 2 5 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1118, '22 1 18 18 1 2 3 -1 2 5 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1119, '22 1 18 18 1 2 22 -1 2 5 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1120, '22 1 18 18 1 2 22 3 -1 2 5 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1121, '22 1 18 1 -1 2 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1122, '22 1 18 1 3 -1 2 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1123, '22 1 18 1 22 -1 2 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1124, '22 1 18 1 22 3 -1 2 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1125, '22 1 18 1 2 -1 2 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1126, '22 1 18 1 2 3 -1 2 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1127, '22 1 18 1 2 22 -1 2 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1128, '22 1 18 1 2 22 3 -1 2 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1129, '22 1 2 0 -1 2 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1130, '22 1 2 0 3 -1 2 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1131, '22 1 2 0 22 -1 2 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1132, '22 1 2 0 22 3 -1 2 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1133, '22 1 2 0 2 -1 2 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1134, '22 1 2 0 2 3 -1 2 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1135, '22 1 2 0 2 22 -1 2 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1136, '22 1 2 0 2 22 3 -1 2 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1137, '22 1 2 1 -1 2 5 5 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1138, '22 1 2 1 3 -1 2 5 5 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1139, '22 1 2 1 22 -1 2 5 5 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1140, '22 1 2 1 22 3 -1 2 5 5 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1141, '22 1 2 1 2 -1 2 5 5 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1142, '22 1 2 1 2 3 -1 2 5 5 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1143, '22 1 2 1 2 22 -1 2 5 5 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1144, '22 1 2 1 2 22 3 -1 2 5 5 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1145, '22 16 -1 2 5 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1146, '22 16 3 -1 2 5 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1147, '22 16 22 -1 2 5 7 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1148, '22 16 22 3 -1 2 5 7 3 -1 2 6');
INSERT INTO pagc_rules (id, rule) VALUES (1149, '22 16 2 -1 2 5 6 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1150, '22 16 2 3 -1 2 5 6 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1151, '22 16 2 22 -1 2 5 6 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1152, '22 16 2 22 3 -1 2 5 6 7 3 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1153, '22 2 1 -1 2 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1154, '22 2 1 3 -1 2 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1155, '22 2 1 22 -1 2 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1156, '22 2 1 22 3 -1 2 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1157, '22 2 18 -1 2 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1158, '22 2 18 3 -1 2 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1159, '22 2 18 22 -1 2 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1160, '22 2 18 22 3 -1 2 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1161, '22 2 2 -1 2 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1162, '22 2 2 3 -1 2 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1163, '22 2 2 22 -1 2 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1164, '22 2 2 22 3 -1 2 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1165, '22 2 22 -1 2 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1166, '22 2 22 3 -1 2 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1167, '22 2 22 22 -1 2 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1168, '22 2 22 22 3 -1 2 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1169, '22 2 22 1 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1170, '22 2 22 1 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1171, '22 2 22 1 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1172, '22 2 22 1 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1173, '22 2 1 22 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1174, '22 2 1 22 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1175, '22 2 1 22 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1176, '22 2 1 22 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1177, '22 2 1 2 -1 2 4 5 5 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1178, '22 2 1 2 3 -1 2 4 5 5 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1179, '22 2 1 2 22 -1 2 4 5 5 7 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1180, '22 2 1 2 22 3 -1 2 4 5 5 7 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1181, '22 2 2 1 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1182, '22 2 2 1 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1183, '22 2 2 1 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1184, '22 2 2 1 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1185, '22 2 24 2 -1 2 4 5 5 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1186, '22 2 24 2 3 -1 2 4 5 5 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1187, '22 2 24 2 22 -1 2 4 5 5 7 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1188, '22 2 24 2 22 3 -1 2 4 5 5 7 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1189, '22 2 0 22 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1190, '22 2 0 22 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1191, '22 2 0 22 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1192, '22 2 0 22 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1193, '22 2 2 24 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1194, '22 2 2 24 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1195, '22 2 2 24 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1196, '22 2 2 24 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1197, '22 2 2 22 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1198, '22 2 2 22 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1199, '22 2 2 22 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1200, '22 2 2 22 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1201, '22 2 2 0 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1202, '22 2 2 0 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1203, '22 2 2 0 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1204, '22 2 2 0 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1205, '22 2 2 18 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1206, '22 2 2 18 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1207, '22 2 2 18 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1208, '22 2 2 18 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1209, '22 2 2 2 -1 2 4 5 5 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1210, '22 2 2 2 3 -1 2 4 5 5 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1211, '22 2 2 2 22 -1 2 4 5 5 7 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1212, '22 2 2 2 22 3 -1 2 4 5 5 7 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1213, '22 2 18 2 -1 2 4 5 5 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1214, '22 2 18 2 3 -1 2 4 5 5 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1215, '22 2 18 2 22 -1 2 4 5 5 7 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1216, '22 2 18 2 22 3 -1 2 4 5 5 7 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1217, '22 2 1 18 2 -1 2 4 5 5 5 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1218, '22 2 1 18 2 3 -1 2 4 5 5 5 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1219, '22 2 1 18 2 22 -1 2 4 5 5 5 7 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1220, '22 2 1 18 2 22 3 -1 2 4 5 5 5 7 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1221, '22 2 0 -1 2 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1222, '22 2 0 3 -1 2 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1223, '22 2 0 22 -1 2 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1224, '22 2 0 22 3 -1 2 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1225, '22 2 0 18 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1226, '22 2 0 18 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1227, '22 2 0 18 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1228, '22 2 0 18 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1229, '22 2 0 1 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1230, '22 2 0 1 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1231, '22 2 0 1 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1232, '22 2 0 1 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1233, '22 2 1 2 2 -1 2 4 5 5 5 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1234, '22 2 1 2 2 3 -1 2 4 5 5 5 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1235, '22 2 1 2 2 22 -1 2 4 5 5 5 7 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1236, '22 2 1 2 2 22 3 -1 2 4 5 5 5 7 3 -1 2 4');
INSERT INTO pagc_rules (id, rule) VALUES (1237, '22 2 22 2 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1238, '22 2 22 2 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1239, '22 2 22 2 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1240, '22 2 22 2 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1241, '22 2 14 -1 2 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1242, '22 2 14 3 -1 2 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1243, '22 2 14 22 -1 2 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1244, '22 2 14 22 3 -1 2 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1245, '22 2 15 1 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1246, '22 2 15 1 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1247, '22 2 15 1 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1248, '22 2 15 1 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1249, '22 2 24 -1 2 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1250, '22 2 24 3 -1 2 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1251, '22 2 24 22 -1 2 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1252, '22 2 24 22 3 -1 2 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1253, '22 2 24 24 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1254, '22 2 24 24 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1255, '22 2 24 24 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1256, '22 2 24 24 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1257, '22 2 24 1 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1258, '22 2 24 1 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1259, '22 2 24 1 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1260, '22 2 24 1 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1261, '22 2 25 -1 2 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1262, '22 2 25 3 -1 2 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1263, '22 2 25 22 -1 2 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1264, '22 2 25 22 3 -1 2 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1265, '22 2 23 -1 2 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1266, '22 2 23 3 -1 2 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1267, '22 2 23 22 -1 2 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1268, '22 2 23 22 3 -1 2 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1269, '22 2 0 13 0 -1 2 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1270, '22 2 0 13 0 3 -1 2 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1271, '22 2 0 13 0 22 -1 2 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1272, '22 2 0 13 0 22 3 -1 2 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1273, '22 2 0 25 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1274, '22 2 0 25 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1275, '22 2 0 25 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1276, '22 2 0 25 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1277, '22 2 11 -1 2 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1278, '22 2 11 3 -1 2 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1279, '22 2 11 22 -1 2 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1280, '22 2 11 22 3 -1 2 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1281, '22 2 3 0 -1 2 4 3 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1282, '22 2 3 0 3 -1 2 4 3 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1283, '22 2 3 0 22 -1 2 4 3 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1284, '22 2 3 0 22 3 -1 2 4 3 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1285, '22 2 3 1 -1 2 4 3 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1286, '22 2 3 1 3 -1 2 4 3 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1287, '22 2 3 1 22 -1 2 4 3 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1288, '22 2 3 1 22 3 -1 2 4 3 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1289, '22 2 18 13 18 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1290, '22 2 18 13 18 3 -1 2 4 5 5 3 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1291, '22 2 18 13 18 22 -1 2 4 5 5 3 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1292, '22 2 18 13 18 22 3 -1 2 4 5 5 3 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1293, '22 2 18 0 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1294, '22 2 18 0 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1295, '22 2 18 0 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1296, '22 2 18 0 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1297, '22 2 18 18 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1298, '22 2 18 18 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1299, '22 2 18 18 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1300, '22 2 18 18 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1301, '22 2 18 18 18 -1 2 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1302, '22 2 18 18 18 3 -1 2 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1303, '22 2 18 18 18 22 -1 2 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1304, '22 2 18 18 18 22 3 -1 2 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1305, '22 2 18 18 1 -1 2 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1306, '22 2 18 18 1 3 -1 2 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1307, '22 2 18 18 1 22 -1 2 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1308, '22 2 18 18 1 22 3 -1 2 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1309, '22 2 18 1 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1310, '22 2 18 1 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1311, '22 2 18 1 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1312, '22 2 18 1 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1313, '22 2 5 -1 2 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1314, '22 2 5 3 -1 2 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1315, '22 2 5 22 -1 2 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1316, '22 2 5 22 3 -1 2 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1317, '22 2 21 -1 2 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1318, '22 2 21 3 -1 2 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1319, '22 2 21 22 -1 2 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1320, '22 2 21 22 3 -1 2 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1321, '22 2 1 13 1 -1 2 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1322, '22 2 1 13 1 3 -1 2 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1323, '22 2 1 13 1 22 -1 2 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1324, '22 2 1 13 1 22 3 -1 2 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1325, '22 2 1 24 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1326, '22 2 1 24 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1327, '22 2 1 24 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1328, '22 2 1 24 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1329, '22 2 1 24 24 -1 2 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1330, '22 2 1 24 24 3 -1 2 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1331, '22 2 1 24 24 22 -1 2 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1332, '22 2 1 24 24 22 3 -1 2 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1333, '22 2 1 24 1 -1 2 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1334, '22 2 1 24 1 3 -1 2 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1335, '22 2 1 24 1 22 -1 2 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1336, '22 2 1 24 1 22 3 -1 2 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1337, '22 2 1 15 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1338, '22 2 1 15 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1339, '22 2 1 15 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1340, '22 2 1 15 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1341, '22 2 1 22 1 -1 2 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1342, '22 2 1 22 1 3 -1 2 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1343, '22 2 1 22 1 22 -1 2 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1344, '22 2 1 22 1 22 3 -1 2 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1345, '22 2 1 25 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1346, '22 2 1 25 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1347, '22 2 1 25 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1348, '22 2 1 25 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1349, '22 2 1 0 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1350, '22 2 1 0 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1351, '22 2 1 0 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1352, '22 2 1 0 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1353, '22 2 1 3 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1354, '22 2 1 3 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1355, '22 2 1 3 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1356, '22 2 1 3 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1357, '22 2 1 18 -1 2 4 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1358, '22 2 1 18 3 -1 2 4 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1359, '22 2 1 18 22 -1 2 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1360, '22 2 1 18 22 3 -1 2 4 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1361, '22 2 1 18 18 1 -1 2 4 5 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1362, '22 2 1 18 18 1 3 -1 2 4 5 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1363, '22 2 1 18 18 1 22 -1 2 4 5 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1364, '22 2 1 18 18 1 22 3 -1 2 4 5 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1365, '22 2 1 18 1 -1 2 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1366, '22 2 1 18 1 3 -1 2 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1367, '22 2 1 18 1 22 -1 2 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1368, '22 2 1 18 1 22 3 -1 2 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1369, '22 2 1 2 0 -1 2 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1370, '22 2 1 2 0 3 -1 2 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1371, '22 2 1 2 0 22 -1 2 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1372, '22 2 1 2 0 22 3 -1 2 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1373, '22 2 1 2 1 -1 2 4 5 5 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1374, '22 2 1 2 1 3 -1 2 4 5 5 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1375, '22 2 1 2 1 22 -1 2 4 5 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1376, '22 2 1 2 1 22 3 -1 2 4 5 5 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1377, '22 2 16 -1 2 4 5 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1378, '22 2 16 3 -1 2 4 5 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1379, '22 2 16 22 -1 2 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1380, '22 2 16 22 3 -1 2 4 5 7 3 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1381, '6 0 -1 4 5 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1382, '6 0 22 -1 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1383, '6 21 -1 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1384, '6 21 22 -1 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1385, '6 21 0 -1 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1386, '6 21 0 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1387, '6 23 -1 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1388, '6 23 22 -1 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1389, '6 0 18 -1 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1390, '6 0 18 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1391, '6 0 0 -1 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1392, '6 0 0 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1393, '6 18 -1 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1394, '6 18 22 -1 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1395, '6 18 0 -1 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1396, '6 18 0 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1397, '6 18 18 -1 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1398, '6 18 18 22 -1 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1399, '6 6 0 -1 3 4 5 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1400, '6 6 0 22 -1 3 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1401, '6 6 21 -1 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1402, '6 6 21 22 -1 3 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1403, '6 6 21 0 -1 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1404, '6 6 21 0 22 -1 3 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1405, '6 6 23 -1 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1406, '6 6 23 22 -1 3 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1407, '6 6 0 18 -1 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1408, '6 6 0 18 22 -1 3 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1409, '6 6 0 0 -1 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1410, '6 6 0 0 22 -1 3 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1411, '6 6 18 -1 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1412, '6 6 18 22 -1 3 4 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1413, '6 6 18 0 -1 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1414, '6 6 18 0 22 -1 3 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1415, '6 6 18 18 -1 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1416, '6 6 18 18 22 -1 3 4 5 5 7 -1 2 9');
INSERT INTO pagc_rules (id, rule) VALUES (1417, '3 6 0 -1 3 4 5 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1418, '3 6 0 22 -1 3 4 5 7 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1419, '3 6 21 -1 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1420, '3 6 21 22 -1 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1421, '3 6 21 0 -1 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1422, '3 6 21 0 22 -1 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1423, '3 6 23 -1 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1424, '3 6 23 22 -1 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1425, '3 6 0 18 -1 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1426, '3 6 0 18 22 -1 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1427, '3 6 0 0 -1 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1428, '3 6 0 0 22 -1 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1429, '3 6 18 -1 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1430, '3 6 18 22 -1 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1431, '3 6 18 0 -1 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1432, '3 6 18 0 22 -1 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1433, '3 6 18 18 -1 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1434, '3 6 18 18 22 -1 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1435, '3 6 6 0 -1 3 3 4 5 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1436, '3 6 6 0 22 -1 3 3 4 5 7 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1437, '3 6 6 21 -1 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1438, '3 6 6 21 22 -1 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1439, '3 6 6 21 0 -1 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1440, '3 6 6 21 0 22 -1 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1441, '3 6 6 23 -1 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1442, '3 6 6 23 22 -1 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1443, '3 6 6 0 18 -1 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1444, '3 6 6 0 18 22 -1 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1445, '3 6 6 0 0 -1 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1446, '3 6 6 0 0 22 -1 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1447, '3 6 6 18 -1 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1448, '3 6 6 18 22 -1 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1449, '3 6 6 18 0 -1 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1450, '3 6 6 18 0 22 -1 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1451, '3 6 6 18 18 -1 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1452, '3 6 6 18 18 22 -1 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1453, '11 6 0 -1 3 4 5 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1454, '11 6 0 22 -1 3 4 5 7 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1455, '11 6 21 -1 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1456, '11 6 21 22 -1 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1457, '11 6 21 0 -1 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1458, '11 6 21 0 22 -1 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1459, '11 6 23 -1 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1460, '11 6 23 22 -1 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1461, '11 6 0 18 -1 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1462, '11 6 0 18 22 -1 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1463, '11 6 0 0 -1 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1464, '11 6 0 0 22 -1 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1465, '11 6 18 -1 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1466, '11 6 18 22 -1 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1467, '11 6 18 0 -1 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1468, '11 6 18 0 22 -1 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1469, '11 6 18 18 -1 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1470, '11 6 18 18 22 -1 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1471, '11 6 6 0 -1 3 3 4 5 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1472, '11 6 6 0 22 -1 3 3 4 5 7 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1473, '11 6 6 21 -1 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1474, '11 6 6 21 22 -1 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1475, '11 6 6 21 0 -1 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1476, '11 6 6 21 0 22 -1 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1477, '11 6 6 23 -1 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1478, '11 6 6 23 22 -1 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1479, '11 6 6 0 18 -1 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1480, '11 6 6 0 18 22 -1 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1481, '11 6 6 0 0 -1 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1482, '11 6 6 0 0 22 -1 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1483, '11 6 6 18 -1 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1484, '11 6 6 18 22 -1 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1485, '11 6 6 18 0 -1 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1486, '11 6 6 18 0 22 -1 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1487, '11 6 6 18 18 -1 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1488, '11 6 6 18 18 22 -1 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1489, '3 11 6 0 -1 3 3 4 5 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1490, '3 11 6 0 22 -1 3 3 4 5 7 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1491, '3 11 6 21 -1 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1492, '3 11 6 21 22 -1 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1493, '3 11 6 21 0 -1 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1494, '3 11 6 21 0 22 -1 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1495, '3 11 6 23 -1 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1496, '3 11 6 23 22 -1 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1497, '3 11 6 0 18 -1 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1498, '3 11 6 0 18 22 -1 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1499, '3 11 6 0 0 -1 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1500, '3 11 6 0 0 22 -1 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1501, '3 11 6 18 -1 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1502, '3 11 6 18 22 -1 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1503, '3 11 6 18 0 -1 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1504, '3 11 6 18 0 22 -1 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1505, '3 11 6 18 18 -1 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1506, '3 11 6 18 18 22 -1 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1507, '3 11 6 6 0 -1 3 3 3 4 5 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1508, '3 11 6 6 0 22 -1 3 3 3 4 5 7 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1509, '3 11 6 6 21 -1 3 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1510, '3 11 6 6 21 22 -1 3 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1511, '3 11 6 6 21 0 -1 3 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1512, '3 11 6 6 21 0 22 -1 3 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1513, '3 11 6 6 23 -1 3 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1514, '3 11 6 6 23 22 -1 3 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1515, '3 11 6 6 0 18 -1 3 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1516, '3 11 6 6 0 18 22 -1 3 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1517, '3 11 6 6 0 0 -1 3 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1518, '3 11 6 6 0 0 22 -1 3 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1519, '3 11 6 6 18 -1 3 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1520, '3 11 6 6 18 22 -1 3 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1521, '3 11 6 6 18 0 -1 3 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1522, '3 11 6 6 18 0 22 -1 3 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1523, '3 11 6 6 18 18 -1 3 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1524, '3 11 6 6 18 18 22 -1 3 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1525, '22 6 0 -1 2 4 5 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1526, '22 6 0 22 -1 2 4 5 7 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1527, '22 6 21 -1 2 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1528, '22 6 21 22 -1 2 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1529, '22 6 21 0 -1 2 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1530, '22 6 21 0 22 -1 2 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1531, '22 6 23 -1 2 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1532, '22 6 23 22 -1 2 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1533, '22 6 0 18 -1 2 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1534, '22 6 0 18 22 -1 2 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1535, '22 6 0 0 -1 2 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1536, '22 6 0 0 22 -1 2 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1537, '22 6 18 -1 2 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1538, '22 6 18 22 -1 2 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1539, '22 6 18 0 -1 2 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1540, '22 6 18 0 22 -1 2 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1541, '22 6 18 18 -1 2 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1542, '22 6 18 18 22 -1 2 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1543, '22 6 6 0 -1 2 3 4 5 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1544, '22 6 6 0 22 -1 2 3 4 5 7 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1545, '22 6 6 21 -1 2 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1546, '22 6 6 21 22 -1 2 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1547, '22 6 6 21 0 -1 2 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1548, '22 6 6 21 0 22 -1 2 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1549, '22 6 6 23 -1 2 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1550, '22 6 6 23 22 -1 2 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1551, '22 6 6 0 18 -1 2 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1552, '22 6 6 0 18 22 -1 2 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1553, '22 6 6 0 0 -1 2 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1554, '22 6 6 0 0 22 -1 2 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1555, '22 6 6 18 -1 2 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1556, '22 6 6 18 22 -1 2 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1557, '22 6 6 18 0 -1 2 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1558, '22 6 6 18 0 22 -1 2 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1559, '22 6 6 18 18 -1 2 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1560, '22 6 6 18 18 22 -1 2 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1561, '22 3 6 0 -1 2 3 4 5 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1562, '22 3 6 0 22 -1 2 3 4 5 7 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1563, '22 3 6 21 -1 2 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1564, '22 3 6 21 22 -1 2 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1565, '22 3 6 21 0 -1 2 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1566, '22 3 6 21 0 22 -1 2 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1567, '22 3 6 23 -1 2 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1568, '22 3 6 23 22 -1 2 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1569, '22 3 6 0 18 -1 2 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1570, '22 3 6 0 18 22 -1 2 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1571, '22 3 6 0 0 -1 2 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1572, '22 3 6 0 0 22 -1 2 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1573, '22 3 6 18 -1 2 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1574, '22 3 6 18 22 -1 2 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1575, '22 3 6 18 0 -1 2 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1576, '22 3 6 18 0 22 -1 2 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1577, '22 3 6 18 18 -1 2 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1578, '22 3 6 18 18 22 -1 2 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1579, '22 3 6 6 0 -1 2 3 3 4 5 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1580, '22 3 6 6 0 22 -1 2 3 3 4 5 7 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1581, '22 3 6 6 21 -1 2 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1582, '22 3 6 6 21 22 -1 2 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1583, '22 3 6 6 21 0 -1 2 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1584, '22 3 6 6 21 0 22 -1 2 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1585, '22 3 6 6 23 -1 2 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1586, '22 3 6 6 23 22 -1 2 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1587, '22 3 6 6 0 18 -1 2 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1588, '22 3 6 6 0 18 22 -1 2 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1589, '22 3 6 6 0 0 -1 2 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1590, '22 3 6 6 0 0 22 -1 2 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1591, '22 3 6 6 18 -1 2 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1592, '22 3 6 6 18 22 -1 2 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1593, '22 3 6 6 18 0 -1 2 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1594, '22 3 6 6 18 0 22 -1 2 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1595, '22 3 6 6 18 18 -1 2 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1596, '22 3 6 6 18 18 22 -1 2 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1597, '22 11 6 0 -1 2 3 4 5 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1598, '22 11 6 0 22 -1 2 3 4 5 7 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1599, '22 11 6 21 -1 2 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1600, '22 11 6 21 22 -1 2 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1601, '22 11 6 21 0 -1 2 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1602, '22 11 6 21 0 22 -1 2 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1603, '22 11 6 23 -1 2 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1604, '22 11 6 23 22 -1 2 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1605, '22 11 6 0 18 -1 2 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1606, '22 11 6 0 18 22 -1 2 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1607, '22 11 6 0 0 -1 2 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1608, '22 11 6 0 0 22 -1 2 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1609, '22 11 6 18 -1 2 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1610, '22 11 6 18 22 -1 2 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1611, '22 11 6 18 0 -1 2 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1612, '22 11 6 18 0 22 -1 2 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1613, '22 11 6 18 18 -1 2 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1614, '22 11 6 18 18 22 -1 2 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1615, '22 11 6 6 0 -1 2 3 3 4 5 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1616, '22 11 6 6 0 22 -1 2 3 3 4 5 7 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1617, '22 11 6 6 21 -1 2 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1618, '22 11 6 6 21 22 -1 2 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1619, '22 11 6 6 21 0 -1 2 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1620, '22 11 6 6 21 0 22 -1 2 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1621, '22 11 6 6 23 -1 2 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1622, '22 11 6 6 23 22 -1 2 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1623, '22 11 6 6 0 18 -1 2 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1624, '22 11 6 6 0 18 22 -1 2 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1625, '22 11 6 6 0 0 -1 2 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1626, '22 11 6 6 0 0 22 -1 2 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1627, '22 11 6 6 18 -1 2 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1628, '22 11 6 6 18 22 -1 2 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1629, '22 11 6 6 18 0 -1 2 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1630, '22 11 6 6 18 0 22 -1 2 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1631, '22 11 6 6 18 18 -1 2 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1632, '22 11 6 6 18 18 22 -1 2 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1633, '22 3 11 6 0 -1 2 3 3 4 5 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1634, '22 3 11 6 0 22 -1 2 3 3 4 5 7 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1635, '22 3 11 6 21 -1 2 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1636, '22 3 11 6 21 22 -1 2 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1637, '22 3 11 6 21 0 -1 2 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1638, '22 3 11 6 21 0 22 -1 2 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1639, '22 3 11 6 23 -1 2 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1640, '22 3 11 6 23 22 -1 2 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1641, '22 3 11 6 0 18 -1 2 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1642, '22 3 11 6 0 18 22 -1 2 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1643, '22 3 11 6 0 0 -1 2 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1644, '22 3 11 6 0 0 22 -1 2 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1645, '22 3 11 6 18 -1 2 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1646, '22 3 11 6 18 22 -1 2 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1647, '22 3 11 6 18 0 -1 2 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1648, '22 3 11 6 18 0 22 -1 2 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1649, '22 3 11 6 18 18 -1 2 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1650, '22 3 11 6 18 18 22 -1 2 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1651, '22 3 11 6 6 0 -1 2 3 3 3 4 5 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1652, '22 3 11 6 6 0 22 -1 2 3 3 3 4 5 7 -1 2 16');
INSERT INTO pagc_rules (id, rule) VALUES (1653, '22 3 11 6 6 21 -1 2 3 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1654, '22 3 11 6 6 21 22 -1 2 3 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1655, '22 3 11 6 6 21 0 -1 2 3 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1656, '22 3 11 6 6 21 0 22 -1 2 3 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1657, '22 3 11 6 6 23 -1 2 3 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1658, '22 3 11 6 6 23 22 -1 2 3 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1659, '22 3 11 6 6 0 18 -1 2 3 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1660, '22 3 11 6 6 0 18 22 -1 2 3 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1661, '22 3 11 6 6 0 0 -1 2 3 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1662, '22 3 11 6 6 0 0 22 -1 2 3 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1663, '22 3 11 6 6 18 -1 2 3 3 3 4 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1664, '22 3 11 6 6 18 22 -1 2 3 3 3 4 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1665, '22 3 11 6 6 18 0 -1 2 3 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1666, '22 3 11 6 6 18 0 22 -1 2 3 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1667, '22 3 11 6 6 18 18 -1 2 3 3 3 4 5 5 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1668, '22 3 11 6 6 18 18 22 -1 2 3 3 3 4 5 5 7 -1 2 12');
INSERT INTO pagc_rules (id, rule) VALUES (1669, '0 1 -1 1 5 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1670, '0 1 22 -1 1 5 7 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1671, '0 1 2 -1 1 5 6 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (1672, '0 1 2 22 -1 1 5 6 7 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (1673, '0 5 -1 1 5 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1674, '0 5 22 -1 1 5 7 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1675, '0 5 2 -1 1 5 6 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (1676, '0 5 2 22 -1 1 5 6 7 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (1677, '0 2 1 -1 1 4 5 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1678, '0 2 1 22 -1 1 4 5 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1679, '0 2 5 -1 1 4 5 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1680, '0 2 5 22 -1 1 4 5 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1681, '0 22 1 -1 1 2 5 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1682, '0 22 1 2 -1 1 2 5 6 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (1683, '0 22 5 -1 1 2 5 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1684, '0 22 5 2 -1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1685, '0 22 2 1 -1 1 2 4 5 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1686, '0 22 2 5 -1 1 2 4 5 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1687, '0 18 1 -1 1 1 5 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1688, '0 18 1 22 -1 1 1 5 7 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1689, '0 18 1 2 -1 1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1690, '0 18 1 2 22 -1 1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1691, '0 18 5 -1 1 1 5 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1692, '0 18 5 22 -1 1 1 5 7 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1693, '0 18 5 2 -1 1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1694, '0 18 5 2 22 -1 1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1695, '0 18 2 1 -1 1 1 4 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (1696, '0 18 2 1 22 -1 1 1 4 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (1697, '0 18 2 5 -1 1 1 4 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (1698, '0 18 2 5 22 -1 1 1 4 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (1699, '0 18 22 1 -1 1 1 2 5 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1700, '0 18 22 1 2 -1 1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1701, '0 18 22 5 -1 1 1 2 5 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1702, '0 18 22 5 2 -1 1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1703, '0 18 22 2 1 -1 1 1 2 4 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (1704, '0 18 22 2 5 -1 1 1 2 4 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (1705, '0 25 1 -1 1 1 5 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1706, '0 25 1 22 -1 1 1 5 7 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1707, '0 25 1 2 -1 1 1 5 6 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1708, '0 25 1 2 22 -1 1 1 5 6 7 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1709, '0 25 5 -1 1 1 5 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1710, '0 25 5 22 -1 1 1 5 7 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1711, '0 25 5 2 -1 1 1 5 6 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1712, '0 25 5 2 22 -1 1 1 5 6 7 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1713, '0 25 2 1 -1 1 1 4 5 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1714, '0 25 2 1 22 -1 1 1 4 5 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1715, '0 25 2 5 -1 1 1 4 5 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1716, '0 25 2 5 22 -1 1 1 4 5 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1717, '0 25 22 1 -1 1 1 2 5 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1718, '0 25 22 1 2 -1 1 1 2 5 6 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1719, '0 25 22 5 -1 1 1 2 5 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1720, '0 25 22 5 2 -1 1 1 2 5 6 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1721, '0 25 22 2 1 -1 1 1 2 4 5 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1722, '0 25 22 2 5 -1 1 1 2 4 5 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1723, '25 1 -1 1 5 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1724, '25 1 22 -1 1 5 7 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1725, '25 1 2 -1 1 5 6 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1726, '25 1 2 22 -1 1 5 6 7 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1727, '25 5 -1 1 5 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1728, '25 5 22 -1 1 5 7 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1729, '25 5 2 -1 1 5 6 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1730, '25 5 2 22 -1 1 5 6 7 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1731, '25 2 1 -1 1 4 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (1732, '25 2 1 22 -1 1 4 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (1733, '25 2 5 -1 1 4 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (1734, '25 2 5 22 -1 1 4 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (1735, '25 22 1 -1 1 2 5 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1736, '25 22 1 2 -1 1 2 5 6 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1737, '25 22 5 -1 1 2 5 -1 1 7');
INSERT INTO pagc_rules (id, rule) VALUES (1738, '25 22 5 2 -1 1 2 5 6 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1739, '25 22 2 1 -1 1 2 4 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (1740, '25 22 2 5 -1 1 2 4 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (1741, '0 0 -1 1 5 -1 1 4');
INSERT INTO pagc_rules (id, rule) VALUES (1742, '0 0 22 -1 1 5 7 -1 1 4');
INSERT INTO pagc_rules (id, rule) VALUES (1743, '0 0 2 -1 1 5 6 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1744, '0 0 2 22 -1 1 5 6 7 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1745, '0 18 -1 1 5 -1 1 6');
INSERT INTO pagc_rules (id, rule) VALUES (1746, '0 18 22 -1 1 5 7 -1 1 6');
INSERT INTO pagc_rules (id, rule) VALUES (1747, '0 18 2 -1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1748, '0 18 2 22 -1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1749, '0 2 0 -1 1 4 5 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1750, '0 2 0 22 -1 1 4 5 7 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1751, '0 2 18 -1 1 4 5 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1752, '0 2 18 22 -1 1 4 5 7 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1753, '0 22 0 -1 1 2 5 -1 1 6');
INSERT INTO pagc_rules (id, rule) VALUES (1754, '0 22 0 22 -1 1 2 5 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1755, '0 22 0 2 -1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1756, '0 22 0 2 22 -1 1 2 5 6 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1757, '0 22 18 -1 1 2 5 -1 1 6');
INSERT INTO pagc_rules (id, rule) VALUES (1758, '0 22 18 22 -1 1 2 5 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1759, '0 22 18 2 -1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1760, '0 22 18 2 22 -1 1 2 5 6 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1761, '0 22 2 0 -1 1 2 4 5 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1762, '0 22 2 0 22 -1 1 2 4 5 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1763, '0 22 2 18 -1 1 2 4 5 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1764, '0 22 2 18 22 -1 1 2 4 5 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1765, '0 18 0 -1 1 1 5 -1 1 3');
INSERT INTO pagc_rules (id, rule) VALUES (1766, '0 18 0 22 -1 1 1 5 7 -1 1 3');
INSERT INTO pagc_rules (id, rule) VALUES (1767, '0 18 0 2 -1 1 1 5 6 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1768, '0 18 0 2 22 -1 1 1 5 6 7 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1769, '0 18 18 -1 1 1 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (1770, '0 18 18 22 -1 1 1 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (1771, '0 18 18 2 -1 1 1 5 6 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1772, '0 18 18 2 22 -1 1 1 5 6 7 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1773, '0 18 2 0 -1 1 1 4 5 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1774, '0 18 2 0 22 -1 1 1 4 5 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (1775, '0 18 2 18 -1 1 1 4 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (1776, '0 18 2 18 22 -1 1 1 4 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (1777, '0 18 22 0 -1 1 1 2 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (1778, '0 18 22 0 2 -1 1 1 2 5 6 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1779, '0 18 22 18 -1 1 1 2 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (1780, '0 18 22 18 2 -1 1 1 2 5 6 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1781, '0 18 22 2 0 -1 1 1 2 4 5 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1782, '0 18 22 2 18 -1 1 1 2 4 5 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1783, '0 25 0 -1 1 1 5 -1 1 3');
INSERT INTO pagc_rules (id, rule) VALUES (1784, '0 25 0 22 -1 1 1 5 7 -1 1 3');
INSERT INTO pagc_rules (id, rule) VALUES (1785, '0 25 0 2 -1 1 1 5 6 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1786, '0 25 0 2 22 -1 1 1 5 6 7 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1787, '0 25 18 -1 1 1 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (1788, '0 25 18 22 -1 1 1 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (1789, '0 25 18 2 -1 1 1 5 6 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1790, '0 25 18 2 22 -1 1 1 5 6 7 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1791, '0 25 2 0 -1 1 1 4 5 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1792, '0 25 2 0 22 -1 1 1 4 5 7 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1793, '0 25 2 18 -1 1 1 4 5 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1794, '0 25 2 18 22 -1 1 1 4 5 7 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1795, '0 25 22 0 -1 1 1 2 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (1796, '0 25 22 0 2 -1 1 1 2 5 6 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1797, '0 25 22 18 -1 1 1 2 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (1798, '0 25 22 18 2 -1 1 1 2 5 6 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1799, '0 25 22 2 0 -1 1 1 2 4 5 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1800, '0 25 22 2 18 -1 1 1 2 4 5 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1801, '25 0 -1 1 5 -1 1 3');
INSERT INTO pagc_rules (id, rule) VALUES (1802, '25 0 22 -1 1 5 7 -1 1 3');
INSERT INTO pagc_rules (id, rule) VALUES (1803, '25 0 2 -1 1 5 6 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1804, '25 0 2 22 -1 1 5 6 7 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1805, '25 18 -1 1 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (1806, '25 18 22 -1 1 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (1807, '25 18 2 -1 1 5 6 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1808, '25 18 2 22 -1 1 5 6 7 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1809, '25 2 0 -1 1 4 5 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1810, '25 2 0 22 -1 1 4 5 7 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1811, '25 2 18 -1 1 4 5 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1812, '25 2 18 22 -1 1 4 5 7 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1813, '25 22 0 -1 1 2 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (1814, '25 22 0 2 -1 1 2 5 6 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1815, '25 22 18 -1 1 2 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (1816, '25 22 18 2 -1 1 2 5 6 -1 1 15');
INSERT INTO pagc_rules (id, rule) VALUES (1817, '25 22 2 0 -1 1 2 4 5 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1818, '25 22 2 18 -1 1 2 4 5 -1 1 14');
INSERT INTO pagc_rules (id, rule) VALUES (1819, '0 6 0 -1 1 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (1820, '0 6 0 22 -1 1 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (1821, '0 6 21 -1 1 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1822, '0 6 21 22 -1 1 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1823, '0 6 21 0 -1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1824, '0 6 21 0 22 -1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1825, '0 6 23 -1 1 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1826, '0 6 23 22 -1 1 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1827, '0 6 0 18 -1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1828, '0 6 0 18 22 -1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1829, '0 6 0 0 -1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1830, '0 6 0 0 22 -1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1831, '0 6 18 -1 1 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1832, '0 6 18 22 -1 1 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1833, '0 6 18 0 -1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1834, '0 6 18 0 22 -1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1835, '0 6 18 18 -1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1836, '0 6 18 18 22 -1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1837, '0 6 6 0 -1 1 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (1838, '0 6 6 0 22 -1 1 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (1839, '0 6 6 21 -1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1840, '0 6 6 21 22 -1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1841, '0 6 6 21 0 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1842, '0 6 6 21 0 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1843, '0 6 6 23 -1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1844, '0 6 6 23 22 -1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1845, '0 6 6 0 18 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1846, '0 6 6 0 18 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1847, '0 6 6 0 0 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1848, '0 6 6 0 0 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1849, '0 6 6 18 -1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1850, '0 6 6 18 22 -1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1851, '0 6 6 18 0 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1852, '0 6 6 18 0 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1853, '0 6 6 18 18 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1854, '0 6 6 18 18 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1855, '0 3 6 0 -1 1 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (1856, '0 3 6 0 22 -1 1 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (1857, '0 3 6 21 -1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1858, '0 3 6 21 22 -1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1859, '0 3 6 21 0 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1860, '0 3 6 21 0 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1861, '0 3 6 23 -1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1862, '0 3 6 23 22 -1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1863, '0 3 6 0 18 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1864, '0 3 6 0 18 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1865, '0 3 6 0 0 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1866, '0 3 6 0 0 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1867, '0 3 6 18 -1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1868, '0 3 6 18 22 -1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1869, '0 3 6 18 0 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1870, '0 3 6 18 0 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1871, '0 3 6 18 18 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1872, '0 3 6 18 18 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1873, '0 3 6 6 0 -1 1 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (1874, '0 3 6 6 0 22 -1 1 3 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (1875, '0 3 6 6 21 -1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1876, '0 3 6 6 21 22 -1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1877, '0 3 6 6 21 0 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1878, '0 3 6 6 21 0 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1879, '0 3 6 6 23 -1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1880, '0 3 6 6 23 22 -1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1881, '0 3 6 6 0 18 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1882, '0 3 6 6 0 18 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1883, '0 3 6 6 0 0 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1884, '0 3 6 6 0 0 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1885, '0 3 6 6 18 -1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1886, '0 3 6 6 18 22 -1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1887, '0 3 6 6 18 0 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1888, '0 3 6 6 18 0 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1889, '0 3 6 6 18 18 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1890, '0 3 6 6 18 18 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1891, '0 11 6 0 -1 1 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (1892, '0 11 6 0 22 -1 1 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (1893, '0 11 6 21 -1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1894, '0 11 6 21 22 -1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1895, '0 11 6 21 0 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1896, '0 11 6 21 0 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1897, '0 11 6 23 -1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1898, '0 11 6 23 22 -1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1899, '0 11 6 0 18 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1900, '0 11 6 0 18 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1901, '0 11 6 0 0 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1902, '0 11 6 0 0 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1903, '0 11 6 18 -1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1904, '0 11 6 18 22 -1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1905, '0 11 6 18 0 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1906, '0 11 6 18 0 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1907, '0 11 6 18 18 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1908, '0 11 6 18 18 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1909, '0 11 6 6 0 -1 1 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (1910, '0 11 6 6 0 22 -1 1 3 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (1911, '0 11 6 6 21 -1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1912, '0 11 6 6 21 22 -1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1913, '0 11 6 6 21 0 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1914, '0 11 6 6 21 0 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1915, '0 11 6 6 23 -1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1916, '0 11 6 6 23 22 -1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1917, '0 11 6 6 0 18 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1918, '0 11 6 6 0 18 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1919, '0 11 6 6 0 0 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1920, '0 11 6 6 0 0 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1921, '0 11 6 6 18 -1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1922, '0 11 6 6 18 22 -1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1923, '0 11 6 6 18 0 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1924, '0 11 6 6 18 0 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1925, '0 11 6 6 18 18 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1926, '0 11 6 6 18 18 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1927, '0 3 11 6 0 -1 1 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (1928, '0 3 11 6 0 22 -1 1 3 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (1929, '0 3 11 6 21 -1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1930, '0 3 11 6 21 22 -1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1931, '0 3 11 6 21 0 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1932, '0 3 11 6 21 0 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1933, '0 3 11 6 23 -1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1934, '0 3 11 6 23 22 -1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1935, '0 3 11 6 0 18 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1936, '0 3 11 6 0 18 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1937, '0 3 11 6 0 0 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1938, '0 3 11 6 0 0 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1939, '0 3 11 6 18 -1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1940, '0 3 11 6 18 22 -1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1941, '0 3 11 6 18 0 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1942, '0 3 11 6 18 0 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1943, '0 3 11 6 18 18 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1944, '0 3 11 6 18 18 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1945, '0 3 11 6 6 0 -1 1 3 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (1946, '0 3 11 6 6 0 22 -1 1 3 3 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (1947, '0 3 11 6 6 21 -1 1 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1948, '0 3 11 6 6 21 22 -1 1 3 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1949, '0 3 11 6 6 21 0 -1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1950, '0 3 11 6 6 21 0 22 -1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1951, '0 3 11 6 6 23 -1 1 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1952, '0 3 11 6 6 23 22 -1 1 3 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1953, '0 3 11 6 6 0 18 -1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1954, '0 3 11 6 6 0 18 22 -1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1955, '0 3 11 6 6 0 0 -1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1956, '0 3 11 6 6 0 0 22 -1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1957, '0 3 11 6 6 18 -1 1 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1958, '0 3 11 6 6 18 22 -1 1 3 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1959, '0 3 11 6 6 18 0 -1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1960, '0 3 11 6 6 18 0 22 -1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1961, '0 3 11 6 6 18 18 -1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1962, '0 3 11 6 6 18 18 22 -1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1963, '0 22 6 0 -1 1 2 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (1964, '0 22 6 21 -1 1 2 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1965, '0 22 6 21 0 -1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1966, '0 22 6 23 -1 1 2 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1967, '0 22 6 0 18 -1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1968, '0 22 6 0 0 -1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1969, '0 22 6 18 -1 1 2 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1970, '0 22 6 18 0 -1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1971, '0 22 6 18 18 -1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1972, '0 22 6 6 0 -1 1 2 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (1973, '0 22 6 6 21 -1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1974, '0 22 6 6 21 0 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1975, '0 22 6 6 23 -1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1976, '0 22 6 6 0 18 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1977, '0 22 6 6 0 0 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1978, '0 22 6 6 18 -1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1979, '0 22 6 6 18 0 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1980, '0 22 6 6 18 18 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1981, '0 22 3 6 0 -1 1 2 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (1982, '0 22 3 6 21 -1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1983, '0 22 3 6 21 0 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1984, '0 22 3 6 23 -1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1985, '0 22 3 6 0 18 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1986, '0 22 3 6 0 0 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1987, '0 22 3 6 18 -1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1988, '0 22 3 6 18 0 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1989, '0 22 3 6 18 18 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1990, '0 22 3 6 6 0 -1 1 2 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (1991, '0 22 3 6 6 21 -1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1992, '0 22 3 6 6 21 0 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1993, '0 22 3 6 6 23 -1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1994, '0 22 3 6 6 0 18 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1995, '0 22 3 6 6 0 0 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1996, '0 22 3 6 6 18 -1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1997, '0 22 3 6 6 18 0 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1998, '0 22 3 6 6 18 18 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (1999, '0 22 11 6 0 -1 1 2 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2000, '0 22 11 6 21 -1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2001, '0 22 11 6 21 0 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2002, '0 22 11 6 23 -1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2003, '0 22 11 6 0 18 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2004, '0 22 11 6 0 0 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2005, '0 22 11 6 18 -1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2006, '0 22 11 6 18 0 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2007, '0 22 11 6 18 18 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2008, '0 22 11 6 6 0 -1 1 2 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2009, '0 22 11 6 6 21 -1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2010, '0 22 11 6 6 21 0 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2011, '0 22 11 6 6 23 -1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2012, '0 22 11 6 6 0 18 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2013, '0 22 11 6 6 0 0 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2014, '0 22 11 6 6 18 -1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2015, '0 22 11 6 6 18 0 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2016, '0 22 11 6 6 18 18 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2017, '0 22 3 11 6 0 -1 1 2 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2018, '0 22 3 11 6 21 -1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2019, '0 22 3 11 6 21 0 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2020, '0 22 3 11 6 23 -1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2021, '0 22 3 11 6 0 18 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2022, '0 22 3 11 6 0 0 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2023, '0 22 3 11 6 18 -1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2024, '0 22 3 11 6 18 0 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2025, '0 22 3 11 6 18 18 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2026, '0 22 3 11 6 6 0 -1 1 2 3 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2027, '0 22 3 11 6 6 21 -1 1 2 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2028, '0 22 3 11 6 6 21 0 -1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2029, '0 22 3 11 6 6 23 -1 1 2 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2030, '0 22 3 11 6 6 0 18 -1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2031, '0 22 3 11 6 6 0 0 -1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2032, '0 22 3 11 6 6 18 -1 1 2 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2033, '0 22 3 11 6 6 18 0 -1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2034, '0 22 3 11 6 6 18 18 -1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2035, '0 18 6 0 -1 1 1 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2036, '0 18 6 0 22 -1 1 1 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2037, '0 18 6 21 -1 1 1 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2038, '0 18 6 21 22 -1 1 1 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2039, '0 18 6 21 0 -1 1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2040, '0 18 6 21 0 22 -1 1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2041, '0 18 6 23 -1 1 1 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2042, '0 18 6 23 22 -1 1 1 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2043, '0 18 6 0 18 -1 1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2044, '0 18 6 0 18 22 -1 1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2045, '0 18 6 0 0 -1 1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2046, '0 18 6 0 0 22 -1 1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2047, '0 18 6 18 -1 1 1 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2048, '0 18 6 18 22 -1 1 1 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2049, '0 18 6 18 0 -1 1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2050, '0 18 6 18 0 22 -1 1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2051, '0 18 6 18 18 -1 1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2052, '0 18 6 18 18 22 -1 1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2053, '0 18 6 6 0 -1 1 1 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2054, '0 18 6 6 0 22 -1 1 1 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2055, '0 18 6 6 21 -1 1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2056, '0 18 6 6 21 22 -1 1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2057, '0 18 6 6 21 0 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2058, '0 18 6 6 21 0 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2059, '0 18 6 6 23 -1 1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2060, '0 18 6 6 23 22 -1 1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2061, '0 18 6 6 0 18 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2062, '0 18 6 6 0 18 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2063, '0 18 6 6 0 0 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2064, '0 18 6 6 0 0 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2065, '0 18 6 6 18 -1 1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2066, '0 18 6 6 18 22 -1 1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2067, '0 18 6 6 18 0 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2068, '0 18 6 6 18 0 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2069, '0 18 6 6 18 18 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2070, '0 18 6 6 18 18 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2071, '0 18 3 6 0 -1 1 1 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2072, '0 18 3 6 0 22 -1 1 1 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2073, '0 18 3 6 21 -1 1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2074, '0 18 3 6 21 22 -1 1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2075, '0 18 3 6 21 0 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2076, '0 18 3 6 21 0 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2077, '0 18 3 6 23 -1 1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2078, '0 18 3 6 23 22 -1 1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2079, '0 18 3 6 0 18 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2080, '0 18 3 6 0 18 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2081, '0 18 3 6 0 0 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2082, '0 18 3 6 0 0 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2083, '0 18 3 6 18 -1 1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2084, '0 18 3 6 18 22 -1 1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2085, '0 18 3 6 18 0 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2086, '0 18 3 6 18 0 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2087, '0 18 3 6 18 18 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2088, '0 18 3 6 18 18 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2089, '0 18 3 6 6 0 -1 1 1 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2090, '0 18 3 6 6 0 22 -1 1 1 3 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2091, '0 18 3 6 6 21 -1 1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2092, '0 18 3 6 6 21 22 -1 1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2093, '0 18 3 6 6 21 0 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2094, '0 18 3 6 6 21 0 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2095, '0 18 3 6 6 23 -1 1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2096, '0 18 3 6 6 23 22 -1 1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2097, '0 18 3 6 6 0 18 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2098, '0 18 3 6 6 0 18 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2099, '0 18 3 6 6 0 0 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2100, '0 18 3 6 6 0 0 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2101, '0 18 3 6 6 18 -1 1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2102, '0 18 3 6 6 18 22 -1 1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2103, '0 18 3 6 6 18 0 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2104, '0 18 3 6 6 18 0 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2105, '0 18 3 6 6 18 18 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2106, '0 18 3 6 6 18 18 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2107, '0 18 11 6 0 -1 1 1 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2108, '0 18 11 6 0 22 -1 1 1 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2109, '0 18 11 6 21 -1 1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2110, '0 18 11 6 21 22 -1 1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2111, '0 18 11 6 21 0 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2112, '0 18 11 6 21 0 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2113, '0 18 11 6 23 -1 1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2114, '0 18 11 6 23 22 -1 1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2115, '0 18 11 6 0 18 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2116, '0 18 11 6 0 18 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2117, '0 18 11 6 0 0 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2118, '0 18 11 6 0 0 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2119, '0 18 11 6 18 -1 1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2120, '0 18 11 6 18 22 -1 1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2121, '0 18 11 6 18 0 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2122, '0 18 11 6 18 0 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2123, '0 18 11 6 18 18 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2124, '0 18 11 6 18 18 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2125, '0 18 11 6 6 0 -1 1 1 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2126, '0 18 11 6 6 0 22 -1 1 1 3 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2127, '0 18 11 6 6 21 -1 1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2128, '0 18 11 6 6 21 22 -1 1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2129, '0 18 11 6 6 21 0 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2130, '0 18 11 6 6 21 0 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2131, '0 18 11 6 6 23 -1 1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2132, '0 18 11 6 6 23 22 -1 1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2133, '0 18 11 6 6 0 18 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2134, '0 18 11 6 6 0 18 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2135, '0 18 11 6 6 0 0 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2136, '0 18 11 6 6 0 0 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2137, '0 18 11 6 6 18 -1 1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2138, '0 18 11 6 6 18 22 -1 1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2139, '0 18 11 6 6 18 0 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2140, '0 18 11 6 6 18 0 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2141, '0 18 11 6 6 18 18 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2142, '0 18 11 6 6 18 18 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2143, '0 18 3 11 6 0 -1 1 1 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2144, '0 18 3 11 6 0 22 -1 1 1 3 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2145, '0 18 3 11 6 21 -1 1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2146, '0 18 3 11 6 21 22 -1 1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2147, '0 18 3 11 6 21 0 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2148, '0 18 3 11 6 21 0 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2149, '0 18 3 11 6 23 -1 1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2150, '0 18 3 11 6 23 22 -1 1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2151, '0 18 3 11 6 0 18 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2152, '0 18 3 11 6 0 18 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2153, '0 18 3 11 6 0 0 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2154, '0 18 3 11 6 0 0 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2155, '0 18 3 11 6 18 -1 1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2156, '0 18 3 11 6 18 22 -1 1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2157, '0 18 3 11 6 18 0 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2158, '0 18 3 11 6 18 0 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2159, '0 18 3 11 6 18 18 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2160, '0 18 3 11 6 18 18 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2161, '0 18 3 11 6 6 0 -1 1 1 3 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2162, '0 18 3 11 6 6 0 22 -1 1 1 3 3 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2163, '0 18 3 11 6 6 21 -1 1 1 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2164, '0 18 3 11 6 6 21 22 -1 1 1 3 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2165, '0 18 3 11 6 6 21 0 -1 1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2166, '0 18 3 11 6 6 21 0 22 -1 1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2167, '0 18 3 11 6 6 23 -1 1 1 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2168, '0 18 3 11 6 6 23 22 -1 1 1 3 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2169, '0 18 3 11 6 6 0 18 -1 1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2170, '0 18 3 11 6 6 0 18 22 -1 1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2171, '0 18 3 11 6 6 0 0 -1 1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2172, '0 18 3 11 6 6 0 0 22 -1 1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2173, '0 18 3 11 6 6 18 -1 1 1 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2174, '0 18 3 11 6 6 18 22 -1 1 1 3 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2175, '0 18 3 11 6 6 18 0 -1 1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2176, '0 18 3 11 6 6 18 0 22 -1 1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2177, '0 18 3 11 6 6 18 18 -1 1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2178, '0 18 3 11 6 6 18 18 22 -1 1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2179, '0 18 22 6 0 -1 1 1 2 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2180, '0 18 22 6 21 -1 1 1 2 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2181, '0 18 22 6 21 0 -1 1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2182, '0 18 22 6 23 -1 1 1 2 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2183, '0 18 22 6 0 18 -1 1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2184, '0 18 22 6 0 0 -1 1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2185, '0 18 22 6 18 -1 1 1 2 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2186, '0 18 22 6 18 0 -1 1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2187, '0 18 22 6 18 18 -1 1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2188, '0 18 22 6 6 0 -1 1 1 2 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2189, '0 18 22 6 6 21 -1 1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2190, '0 18 22 6 6 21 0 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2191, '0 18 22 6 6 23 -1 1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2192, '0 18 22 6 6 0 18 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2193, '0 18 22 6 6 0 0 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2194, '0 18 22 6 6 18 -1 1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2195, '0 18 22 6 6 18 0 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2196, '0 18 22 6 6 18 18 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2197, '0 18 22 3 6 0 -1 1 1 2 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2198, '0 18 22 3 6 21 -1 1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2199, '0 18 22 3 6 21 0 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2200, '0 18 22 3 6 23 -1 1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2201, '0 18 22 3 6 0 18 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2202, '0 18 22 3 6 0 0 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2203, '0 18 22 3 6 18 -1 1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2204, '0 18 22 3 6 18 0 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2205, '0 18 22 3 6 18 18 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2206, '0 18 22 3 6 6 0 -1 1 1 2 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2207, '0 18 22 3 6 6 21 -1 1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2208, '0 18 22 3 6 6 21 0 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2209, '0 18 22 3 6 6 23 -1 1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2210, '0 18 22 3 6 6 0 18 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2211, '0 18 22 3 6 6 0 0 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2212, '0 18 22 3 6 6 18 -1 1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2213, '0 18 22 3 6 6 18 0 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2214, '0 18 22 3 6 6 18 18 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2215, '0 18 22 11 6 0 -1 1 1 2 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2216, '0 18 22 11 6 21 -1 1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2217, '0 18 22 11 6 21 0 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2218, '0 18 22 11 6 23 -1 1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2219, '0 18 22 11 6 0 18 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2220, '0 18 22 11 6 0 0 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2221, '0 18 22 11 6 18 -1 1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2222, '0 18 22 11 6 18 0 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2223, '0 18 22 11 6 18 18 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2224, '0 18 22 11 6 6 0 -1 1 1 2 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2225, '0 18 22 11 6 6 21 -1 1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2226, '0 18 22 11 6 6 21 0 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2227, '0 18 22 11 6 6 23 -1 1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2228, '0 18 22 11 6 6 0 18 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2229, '0 18 22 11 6 6 0 0 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2230, '0 18 22 11 6 6 18 -1 1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2231, '0 18 22 11 6 6 18 0 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2232, '0 18 22 11 6 6 18 18 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2233, '0 18 22 3 11 6 0 -1 1 1 2 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2234, '0 18 22 3 11 6 21 -1 1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2235, '0 18 22 3 11 6 21 0 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2236, '0 18 22 3 11 6 23 -1 1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2237, '0 18 22 3 11 6 0 18 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2238, '0 18 22 3 11 6 0 0 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2239, '0 18 22 3 11 6 18 -1 1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2240, '0 18 22 3 11 6 18 0 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2241, '0 18 22 3 11 6 18 18 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2242, '0 18 22 3 11 6 6 0 -1 1 1 2 3 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2243, '0 18 22 3 11 6 6 21 -1 1 1 2 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2244, '0 18 22 3 11 6 6 21 0 -1 1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2245, '0 18 22 3 11 6 6 23 -1 1 1 2 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2246, '0 18 22 3 11 6 6 0 18 -1 1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2247, '0 18 22 3 11 6 6 0 0 -1 1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2248, '0 18 22 3 11 6 6 18 -1 1 1 2 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2249, '0 18 22 3 11 6 6 18 0 -1 1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2250, '0 18 22 3 11 6 6 18 18 -1 1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2251, '0 25 6 0 -1 1 1 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2252, '0 25 6 0 22 -1 1 1 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2253, '0 25 6 21 -1 1 1 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2254, '0 25 6 21 22 -1 1 1 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2255, '0 25 6 21 0 -1 1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2256, '0 25 6 21 0 22 -1 1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2257, '0 25 6 23 -1 1 1 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2258, '0 25 6 23 22 -1 1 1 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2259, '0 25 6 0 18 -1 1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2260, '0 25 6 0 18 22 -1 1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2261, '0 25 6 0 0 -1 1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2262, '0 25 6 0 0 22 -1 1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2263, '0 25 6 18 -1 1 1 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2264, '0 25 6 18 22 -1 1 1 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2265, '0 25 6 18 0 -1 1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2266, '0 25 6 18 0 22 -1 1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2267, '0 25 6 18 18 -1 1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2268, '0 25 6 18 18 22 -1 1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2269, '0 25 6 6 0 -1 1 1 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2270, '0 25 6 6 0 22 -1 1 1 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2271, '0 25 6 6 21 -1 1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2272, '0 25 6 6 21 22 -1 1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2273, '0 25 6 6 21 0 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2274, '0 25 6 6 21 0 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2275, '0 25 6 6 23 -1 1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2276, '0 25 6 6 23 22 -1 1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2277, '0 25 6 6 0 18 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2278, '0 25 6 6 0 18 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2279, '0 25 6 6 0 0 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2280, '0 25 6 6 0 0 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2281, '0 25 6 6 18 -1 1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2282, '0 25 6 6 18 22 -1 1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2283, '0 25 6 6 18 0 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2284, '0 25 6 6 18 0 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2285, '0 25 6 6 18 18 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2286, '0 25 6 6 18 18 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2287, '0 25 3 6 0 -1 1 1 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2288, '0 25 3 6 0 22 -1 1 1 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2289, '0 25 3 6 21 -1 1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2290, '0 25 3 6 21 22 -1 1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2291, '0 25 3 6 21 0 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2292, '0 25 3 6 21 0 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2293, '0 25 3 6 23 -1 1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2294, '0 25 3 6 23 22 -1 1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2295, '0 25 3 6 0 18 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2296, '0 25 3 6 0 18 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2297, '0 25 3 6 0 0 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2298, '0 25 3 6 0 0 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2299, '0 25 3 6 18 -1 1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2300, '0 25 3 6 18 22 -1 1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2301, '0 25 3 6 18 0 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2302, '0 25 3 6 18 0 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2303, '0 25 3 6 18 18 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2304, '0 25 3 6 18 18 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2305, '0 25 3 6 6 0 -1 1 1 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2306, '0 25 3 6 6 0 22 -1 1 1 3 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2307, '0 25 3 6 6 21 -1 1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2308, '0 25 3 6 6 21 22 -1 1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2309, '0 25 3 6 6 21 0 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2310, '0 25 3 6 6 21 0 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2311, '0 25 3 6 6 23 -1 1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2312, '0 25 3 6 6 23 22 -1 1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2313, '0 25 3 6 6 0 18 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2314, '0 25 3 6 6 0 18 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2315, '0 25 3 6 6 0 0 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2316, '0 25 3 6 6 0 0 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2317, '0 25 3 6 6 18 -1 1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2318, '0 25 3 6 6 18 22 -1 1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2319, '0 25 3 6 6 18 0 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2320, '0 25 3 6 6 18 0 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2321, '0 25 3 6 6 18 18 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2322, '0 25 3 6 6 18 18 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2323, '0 25 11 6 0 -1 1 1 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2324, '0 25 11 6 0 22 -1 1 1 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2325, '0 25 11 6 21 -1 1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2326, '0 25 11 6 21 22 -1 1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2327, '0 25 11 6 21 0 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2328, '0 25 11 6 21 0 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2329, '0 25 11 6 23 -1 1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2330, '0 25 11 6 23 22 -1 1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2331, '0 25 11 6 0 18 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2332, '0 25 11 6 0 18 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2333, '0 25 11 6 0 0 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2334, '0 25 11 6 0 0 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2335, '0 25 11 6 18 -1 1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2336, '0 25 11 6 18 22 -1 1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2337, '0 25 11 6 18 0 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2338, '0 25 11 6 18 0 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2339, '0 25 11 6 18 18 -1 1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2340, '0 25 11 6 18 18 22 -1 1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2341, '0 25 11 6 6 0 -1 1 1 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2342, '0 25 11 6 6 0 22 -1 1 1 3 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2343, '0 25 11 6 6 21 -1 1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2344, '0 25 11 6 6 21 22 -1 1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2345, '0 25 11 6 6 21 0 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2346, '0 25 11 6 6 21 0 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2347, '0 25 11 6 6 23 -1 1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2348, '0 25 11 6 6 23 22 -1 1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2349, '0 25 11 6 6 0 18 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2350, '0 25 11 6 6 0 18 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2351, '0 25 11 6 6 0 0 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2352, '0 25 11 6 6 0 0 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2353, '0 25 11 6 6 18 -1 1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2354, '0 25 11 6 6 18 22 -1 1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2355, '0 25 11 6 6 18 0 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2356, '0 25 11 6 6 18 0 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2357, '0 25 11 6 6 18 18 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2358, '0 25 11 6 6 18 18 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2359, '0 25 3 11 6 0 -1 1 1 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2360, '0 25 3 11 6 0 22 -1 1 1 3 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2361, '0 25 3 11 6 21 -1 1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2362, '0 25 3 11 6 21 22 -1 1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2363, '0 25 3 11 6 21 0 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2364, '0 25 3 11 6 21 0 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2365, '0 25 3 11 6 23 -1 1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2366, '0 25 3 11 6 23 22 -1 1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2367, '0 25 3 11 6 0 18 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2368, '0 25 3 11 6 0 18 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2369, '0 25 3 11 6 0 0 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2370, '0 25 3 11 6 0 0 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2371, '0 25 3 11 6 18 -1 1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2372, '0 25 3 11 6 18 22 -1 1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2373, '0 25 3 11 6 18 0 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2374, '0 25 3 11 6 18 0 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2375, '0 25 3 11 6 18 18 -1 1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2376, '0 25 3 11 6 18 18 22 -1 1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2377, '0 25 3 11 6 6 0 -1 1 1 3 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2378, '0 25 3 11 6 6 0 22 -1 1 1 3 3 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2379, '0 25 3 11 6 6 21 -1 1 1 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2380, '0 25 3 11 6 6 21 22 -1 1 1 3 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2381, '0 25 3 11 6 6 21 0 -1 1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2382, '0 25 3 11 6 6 21 0 22 -1 1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2383, '0 25 3 11 6 6 23 -1 1 1 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2384, '0 25 3 11 6 6 23 22 -1 1 1 3 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2385, '0 25 3 11 6 6 0 18 -1 1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2386, '0 25 3 11 6 6 0 18 22 -1 1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2387, '0 25 3 11 6 6 0 0 -1 1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2388, '0 25 3 11 6 6 0 0 22 -1 1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2389, '0 25 3 11 6 6 18 -1 1 1 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2390, '0 25 3 11 6 6 18 22 -1 1 1 3 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2391, '0 25 3 11 6 6 18 0 -1 1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2392, '0 25 3 11 6 6 18 0 22 -1 1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2393, '0 25 3 11 6 6 18 18 -1 1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2394, '0 25 3 11 6 6 18 18 22 -1 1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2395, '0 25 22 6 0 -1 1 1 2 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2396, '0 25 22 6 21 -1 1 1 2 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2397, '0 25 22 6 21 0 -1 1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2398, '0 25 22 6 23 -1 1 1 2 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2399, '0 25 22 6 0 18 -1 1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2400, '0 25 22 6 0 0 -1 1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2401, '0 25 22 6 18 -1 1 1 2 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2402, '0 25 22 6 18 0 -1 1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2403, '0 25 22 6 18 18 -1 1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2404, '0 25 22 6 6 0 -1 1 1 2 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2405, '0 25 22 6 6 21 -1 1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2406, '0 25 22 6 6 21 0 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2407, '0 25 22 6 6 23 -1 1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2408, '0 25 22 6 6 0 18 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2409, '0 25 22 6 6 0 0 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2410, '0 25 22 6 6 18 -1 1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2411, '0 25 22 6 6 18 0 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2412, '0 25 22 6 6 18 18 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2413, '0 25 22 3 6 0 -1 1 1 2 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2414, '0 25 22 3 6 21 -1 1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2415, '0 25 22 3 6 21 0 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2416, '0 25 22 3 6 23 -1 1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2417, '0 25 22 3 6 0 18 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2418, '0 25 22 3 6 0 0 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2419, '0 25 22 3 6 18 -1 1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2420, '0 25 22 3 6 18 0 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2421, '0 25 22 3 6 18 18 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2422, '0 25 22 3 6 6 0 -1 1 1 2 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2423, '0 25 22 3 6 6 21 -1 1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2424, '0 25 22 3 6 6 21 0 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2425, '0 25 22 3 6 6 23 -1 1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2426, '0 25 22 3 6 6 0 18 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2427, '0 25 22 3 6 6 0 0 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2428, '0 25 22 3 6 6 18 -1 1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2429, '0 25 22 3 6 6 18 0 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2430, '0 25 22 3 6 6 18 18 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2431, '0 25 22 11 6 0 -1 1 1 2 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2432, '0 25 22 11 6 21 -1 1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2433, '0 25 22 11 6 21 0 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2434, '0 25 22 11 6 23 -1 1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2435, '0 25 22 11 6 0 18 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2436, '0 25 22 11 6 0 0 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2437, '0 25 22 11 6 18 -1 1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2438, '0 25 22 11 6 18 0 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2439, '0 25 22 11 6 18 18 -1 1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2440, '0 25 22 11 6 6 0 -1 1 1 2 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2441, '0 25 22 11 6 6 21 -1 1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2442, '0 25 22 11 6 6 21 0 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2443, '0 25 22 11 6 6 23 -1 1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2444, '0 25 22 11 6 6 0 18 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2445, '0 25 22 11 6 6 0 0 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2446, '0 25 22 11 6 6 18 -1 1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2447, '0 25 22 11 6 6 18 0 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2448, '0 25 22 11 6 6 18 18 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2449, '0 25 22 3 11 6 0 -1 1 1 2 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2450, '0 25 22 3 11 6 21 -1 1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2451, '0 25 22 3 11 6 21 0 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2452, '0 25 22 3 11 6 23 -1 1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2453, '0 25 22 3 11 6 0 18 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2454, '0 25 22 3 11 6 0 0 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2455, '0 25 22 3 11 6 18 -1 1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2456, '0 25 22 3 11 6 18 0 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2457, '0 25 22 3 11 6 18 18 -1 1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2458, '0 25 22 3 11 6 6 0 -1 1 1 2 3 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2459, '0 25 22 3 11 6 6 21 -1 1 1 2 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2460, '0 25 22 3 11 6 6 21 0 -1 1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2461, '0 25 22 3 11 6 6 23 -1 1 1 2 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2462, '0 25 22 3 11 6 6 0 18 -1 1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2463, '0 25 22 3 11 6 6 0 0 -1 1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2464, '0 25 22 3 11 6 6 18 -1 1 1 2 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2465, '0 25 22 3 11 6 6 18 0 -1 1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2466, '0 25 22 3 11 6 6 18 18 -1 1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2467, '25 6 0 -1 1 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2468, '25 6 0 22 -1 1 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2469, '25 6 21 -1 1 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2470, '25 6 21 22 -1 1 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2471, '25 6 21 0 -1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2472, '25 6 21 0 22 -1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2473, '25 6 23 -1 1 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2474, '25 6 23 22 -1 1 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2475, '25 6 0 18 -1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2476, '25 6 0 18 22 -1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2477, '25 6 0 0 -1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2478, '25 6 0 0 22 -1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2479, '25 6 18 -1 1 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2480, '25 6 18 22 -1 1 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2481, '25 6 18 0 -1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2482, '25 6 18 0 22 -1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2483, '25 6 18 18 -1 1 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2484, '25 6 18 18 22 -1 1 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2485, '25 6 6 0 -1 1 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2486, '25 6 6 0 22 -1 1 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2487, '25 6 6 21 -1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2488, '25 6 6 21 22 -1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2489, '25 6 6 21 0 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2490, '25 6 6 21 0 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2491, '25 6 6 23 -1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2492, '25 6 6 23 22 -1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2493, '25 6 6 0 18 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2494, '25 6 6 0 18 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2495, '25 6 6 0 0 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2496, '25 6 6 0 0 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2497, '25 6 6 18 -1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2498, '25 6 6 18 22 -1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2499, '25 6 6 18 0 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2500, '25 6 6 18 0 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2501, '25 6 6 18 18 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2502, '25 6 6 18 18 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2503, '25 3 6 0 -1 1 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2504, '25 3 6 0 22 -1 1 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2505, '25 3 6 21 -1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2506, '25 3 6 21 22 -1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2507, '25 3 6 21 0 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2508, '25 3 6 21 0 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2509, '25 3 6 23 -1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2510, '25 3 6 23 22 -1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2511, '25 3 6 0 18 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2512, '25 3 6 0 18 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2513, '25 3 6 0 0 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2514, '25 3 6 0 0 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2515, '25 3 6 18 -1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2516, '25 3 6 18 22 -1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2517, '25 3 6 18 0 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2518, '25 3 6 18 0 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2519, '25 3 6 18 18 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2520, '25 3 6 18 18 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2521, '25 3 6 6 0 -1 1 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2522, '25 3 6 6 0 22 -1 1 3 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2523, '25 3 6 6 21 -1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2524, '25 3 6 6 21 22 -1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2525, '25 3 6 6 21 0 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2526, '25 3 6 6 21 0 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2527, '25 3 6 6 23 -1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2528, '25 3 6 6 23 22 -1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2529, '25 3 6 6 0 18 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2530, '25 3 6 6 0 18 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2531, '25 3 6 6 0 0 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2532, '25 3 6 6 0 0 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2533, '25 3 6 6 18 -1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2534, '25 3 6 6 18 22 -1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2535, '25 3 6 6 18 0 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2536, '25 3 6 6 18 0 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2537, '25 3 6 6 18 18 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2538, '25 3 6 6 18 18 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2539, '25 11 6 0 -1 1 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2540, '25 11 6 0 22 -1 1 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2541, '25 11 6 21 -1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2542, '25 11 6 21 22 -1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2543, '25 11 6 21 0 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2544, '25 11 6 21 0 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2545, '25 11 6 23 -1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2546, '25 11 6 23 22 -1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2547, '25 11 6 0 18 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2548, '25 11 6 0 18 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2549, '25 11 6 0 0 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2550, '25 11 6 0 0 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2551, '25 11 6 18 -1 1 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2552, '25 11 6 18 22 -1 1 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2553, '25 11 6 18 0 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2554, '25 11 6 18 0 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2555, '25 11 6 18 18 -1 1 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2556, '25 11 6 18 18 22 -1 1 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2557, '25 11 6 6 0 -1 1 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2558, '25 11 6 6 0 22 -1 1 3 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2559, '25 11 6 6 21 -1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2560, '25 11 6 6 21 22 -1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2561, '25 11 6 6 21 0 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2562, '25 11 6 6 21 0 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2563, '25 11 6 6 23 -1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2564, '25 11 6 6 23 22 -1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2565, '25 11 6 6 0 18 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2566, '25 11 6 6 0 18 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2567, '25 11 6 6 0 0 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2568, '25 11 6 6 0 0 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2569, '25 11 6 6 18 -1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2570, '25 11 6 6 18 22 -1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2571, '25 11 6 6 18 0 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2572, '25 11 6 6 18 0 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2573, '25 11 6 6 18 18 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2574, '25 11 6 6 18 18 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2575, '25 3 11 6 0 -1 1 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2576, '25 3 11 6 0 22 -1 1 3 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2577, '25 3 11 6 21 -1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2578, '25 3 11 6 21 22 -1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2579, '25 3 11 6 21 0 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2580, '25 3 11 6 21 0 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2581, '25 3 11 6 23 -1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2582, '25 3 11 6 23 22 -1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2583, '25 3 11 6 0 18 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2584, '25 3 11 6 0 18 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2585, '25 3 11 6 0 0 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2586, '25 3 11 6 0 0 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2587, '25 3 11 6 18 -1 1 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2588, '25 3 11 6 18 22 -1 1 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2589, '25 3 11 6 18 0 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2590, '25 3 11 6 18 0 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2591, '25 3 11 6 18 18 -1 1 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2592, '25 3 11 6 18 18 22 -1 1 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2593, '25 3 11 6 6 0 -1 1 3 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2594, '25 3 11 6 6 0 22 -1 1 3 3 3 4 5 7 -1 1 12');
INSERT INTO pagc_rules (id, rule) VALUES (2595, '25 3 11 6 6 21 -1 1 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2596, '25 3 11 6 6 21 22 -1 1 3 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2597, '25 3 11 6 6 21 0 -1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2598, '25 3 11 6 6 21 0 22 -1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2599, '25 3 11 6 6 23 -1 1 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2600, '25 3 11 6 6 23 22 -1 1 3 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2601, '25 3 11 6 6 0 18 -1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2602, '25 3 11 6 6 0 18 22 -1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2603, '25 3 11 6 6 0 0 -1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2604, '25 3 11 6 6 0 0 22 -1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2605, '25 3 11 6 6 18 -1 1 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2606, '25 3 11 6 6 18 22 -1 1 3 3 3 4 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2607, '25 3 11 6 6 18 0 -1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2608, '25 3 11 6 6 18 0 22 -1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2609, '25 3 11 6 6 18 18 -1 1 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2610, '25 3 11 6 6 18 18 22 -1 1 3 3 3 4 5 5 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2611, '25 22 6 0 -1 1 2 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2612, '25 22 6 21 -1 1 2 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2613, '25 22 6 21 0 -1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2614, '25 22 6 23 -1 1 2 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2615, '25 22 6 0 18 -1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2616, '25 22 6 0 0 -1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2617, '25 22 6 18 -1 1 2 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2618, '25 22 6 18 0 -1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2619, '25 22 6 18 18 -1 1 2 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2620, '25 22 6 6 0 -1 1 2 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2621, '25 22 6 6 21 -1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2622, '25 22 6 6 21 0 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2623, '25 22 6 6 23 -1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2624, '25 22 6 6 0 18 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2625, '25 22 6 6 0 0 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2626, '25 22 6 6 18 -1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2627, '25 22 6 6 18 0 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2628, '25 22 6 6 18 18 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2629, '25 22 3 6 0 -1 1 2 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2630, '25 22 3 6 21 -1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2631, '25 22 3 6 21 0 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2632, '25 22 3 6 23 -1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2633, '25 22 3 6 0 18 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2634, '25 22 3 6 0 0 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2635, '25 22 3 6 18 -1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2636, '25 22 3 6 18 0 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2637, '25 22 3 6 18 18 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2638, '25 22 3 6 6 0 -1 1 2 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2639, '25 22 3 6 6 21 -1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2640, '25 22 3 6 6 21 0 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2641, '25 22 3 6 6 23 -1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2642, '25 22 3 6 6 0 18 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2643, '25 22 3 6 6 0 0 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2644, '25 22 3 6 6 18 -1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2645, '25 22 3 6 6 18 0 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2646, '25 22 3 6 6 18 18 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2647, '25 22 11 6 0 -1 1 2 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2648, '25 22 11 6 21 -1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2649, '25 22 11 6 21 0 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2650, '25 22 11 6 23 -1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2651, '25 22 11 6 0 18 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2652, '25 22 11 6 0 0 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2653, '25 22 11 6 18 -1 1 2 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2654, '25 22 11 6 18 0 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2655, '25 22 11 6 18 18 -1 1 2 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2656, '25 22 11 6 6 0 -1 1 2 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2657, '25 22 11 6 6 21 -1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2658, '25 22 11 6 6 21 0 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2659, '25 22 11 6 6 23 -1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2660, '25 22 11 6 6 0 18 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2661, '25 22 11 6 6 0 0 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2662, '25 22 11 6 6 18 -1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2663, '25 22 11 6 6 18 0 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2664, '25 22 11 6 6 18 18 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2665, '25 22 3 11 6 0 -1 1 2 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2666, '25 22 3 11 6 21 -1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2667, '25 22 3 11 6 21 0 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2668, '25 22 3 11 6 23 -1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2669, '25 22 3 11 6 0 18 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2670, '25 22 3 11 6 0 0 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2671, '25 22 3 11 6 18 -1 1 2 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2672, '25 22 3 11 6 18 0 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2673, '25 22 3 11 6 18 18 -1 1 2 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2674, '25 22 3 11 6 6 0 -1 1 2 3 3 3 4 5 -1 1 17');
INSERT INTO pagc_rules (id, rule) VALUES (2675, '25 22 3 11 6 6 21 -1 1 2 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2676, '25 22 3 11 6 6 21 0 -1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2677, '25 22 3 11 6 6 23 -1 1 2 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2678, '25 22 3 11 6 6 0 18 -1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2679, '25 22 3 11 6 6 0 0 -1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2680, '25 22 3 11 6 6 18 -1 1 2 3 3 3 4 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2681, '25 22 3 11 6 6 18 0 -1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2682, '25 22 3 11 6 6 18 18 -1 1 2 3 3 3 4 5 5 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2683, '0 22 -1 1 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2684, '0 22 22 -1 1 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2685, '0 22 1 -1 1 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2686, '0 22 1 22 -1 1 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2687, '0 15 -1 1 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2688, '0 15 22 -1 1 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2689, '0 18 18 1 -1 1 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2690, '0 18 18 1 22 -1 1 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2691, '0 18 1 -1 1 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2692, '0 18 1 22 -1 1 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2693, '0 2 -1 1 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2694, '0 2 22 -1 1 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2695, '0 1 13 1 -1 1 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2696, '0 1 13 1 22 -1 1 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2697, '0 1 18 -1 1 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2698, '0 1 18 22 -1 1 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2699, '0 1 18 1 -1 1 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2700, '0 1 18 1 22 -1 1 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2701, '0 22 22 -1 1 2 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2702, '0 22 22 22 -1 1 2 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2703, '0 22 22 1 -1 1 2 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2704, '0 22 22 1 22 -1 1 2 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2705, '0 22 15 -1 1 2 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2706, '0 22 15 22 -1 1 2 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2707, '0 22 18 18 1 -1 1 2 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2708, '0 22 18 18 1 22 -1 1 2 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2709, '0 22 18 1 -1 1 2 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2710, '0 22 18 1 22 -1 1 2 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2711, '0 22 2 -1 1 2 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2712, '0 22 2 22 -1 1 2 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2713, '0 22 1 13 1 -1 1 2 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2714, '0 22 1 13 1 22 -1 1 2 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2715, '0 22 1 18 -1 1 2 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2716, '0 22 1 18 22 -1 1 2 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2717, '0 22 1 18 1 -1 1 2 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2718, '0 22 1 18 1 22 -1 1 2 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2719, '0 18 22 -1 1 1 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2720, '0 18 22 22 -1 1 1 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2721, '0 18 22 1 -1 1 1 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2722, '0 18 22 1 22 -1 1 1 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2723, '0 18 15 -1 1 1 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2724, '0 18 15 22 -1 1 1 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2725, '0 18 18 18 1 -1 1 1 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2726, '0 18 18 18 1 22 -1 1 1 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2727, '0 18 18 1 -1 1 1 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2728, '0 18 18 1 22 -1 1 1 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2729, '0 18 2 -1 1 1 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2730, '0 18 2 22 -1 1 1 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2731, '0 18 1 13 1 -1 1 1 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2732, '0 18 1 13 1 22 -1 1 1 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2733, '0 18 1 18 -1 1 1 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2734, '0 18 1 18 22 -1 1 1 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2735, '0 18 1 18 1 -1 1 1 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2736, '0 18 1 18 1 22 -1 1 1 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2737, '0 18 22 22 -1 1 1 2 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2738, '0 18 22 22 22 -1 1 1 2 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2739, '0 18 22 22 1 -1 1 1 2 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2740, '0 18 22 22 1 22 -1 1 1 2 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2741, '0 18 22 15 -1 1 1 2 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2742, '0 18 22 15 22 -1 1 1 2 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2743, '0 18 22 18 18 1 -1 1 1 2 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2744, '0 18 22 18 18 1 22 -1 1 1 2 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2745, '0 18 22 18 1 -1 1 1 2 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2746, '0 18 22 18 1 22 -1 1 1 2 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2747, '0 18 22 2 -1 1 1 2 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2748, '0 18 22 2 22 -1 1 1 2 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2749, '0 18 22 1 13 1 -1 1 1 2 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2750, '0 18 22 1 13 1 22 -1 1 1 2 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2751, '0 18 22 1 18 -1 1 1 2 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2752, '0 18 22 1 18 22 -1 1 1 2 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2753, '0 18 22 1 18 1 -1 1 1 2 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2754, '0 18 22 1 18 1 22 -1 1 1 2 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2755, '0 25 22 -1 1 1 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2756, '0 25 22 22 -1 1 1 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2757, '0 25 22 1 -1 1 1 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2758, '0 25 22 1 22 -1 1 1 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2759, '0 25 15 -1 1 1 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2760, '0 25 15 22 -1 1 1 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2761, '0 25 18 18 1 -1 1 1 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2762, '0 25 18 18 1 22 -1 1 1 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2763, '0 25 18 1 -1 1 1 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2764, '0 25 18 1 22 -1 1 1 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2765, '0 25 2 -1 1 1 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2766, '0 25 2 22 -1 1 1 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2767, '0 25 1 13 1 -1 1 1 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2768, '0 25 1 13 1 22 -1 1 1 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2769, '0 25 1 18 -1 1 1 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2770, '0 25 1 18 22 -1 1 1 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2771, '0 25 1 18 1 -1 1 1 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2772, '0 25 1 18 1 22 -1 1 1 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2773, '0 25 22 22 -1 1 1 2 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2774, '0 25 22 22 22 -1 1 1 2 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2775, '0 25 22 22 1 -1 1 1 2 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2776, '0 25 22 22 1 22 -1 1 1 2 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2777, '0 25 22 15 -1 1 1 2 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2778, '0 25 22 15 22 -1 1 1 2 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2779, '0 25 22 18 18 1 -1 1 1 2 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2780, '0 25 22 18 18 1 22 -1 1 1 2 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2781, '0 25 22 18 1 -1 1 1 2 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2782, '0 25 22 18 1 22 -1 1 1 2 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2783, '0 25 22 2 -1 1 1 2 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2784, '0 25 22 2 22 -1 1 1 2 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2785, '0 25 22 1 13 1 -1 1 1 2 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2786, '0 25 22 1 13 1 22 -1 1 1 2 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2787, '0 25 22 1 18 -1 1 1 2 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2788, '0 25 22 1 18 22 -1 1 1 2 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2789, '0 25 22 1 18 1 -1 1 1 2 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2790, '0 25 22 1 18 1 22 -1 1 1 2 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2791, '25 22 -1 1 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2792, '25 22 22 -1 1 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2793, '25 22 1 -1 1 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2794, '25 22 1 22 -1 1 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2795, '25 15 -1 1 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2796, '25 15 22 -1 1 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2797, '25 18 18 1 -1 1 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2798, '25 18 18 1 22 -1 1 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2799, '25 18 1 -1 1 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2800, '25 18 1 22 -1 1 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2801, '25 2 -1 1 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2802, '25 2 22 -1 1 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2803, '25 1 13 1 -1 1 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2804, '25 1 13 1 22 -1 1 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2805, '25 1 18 -1 1 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2806, '25 1 18 22 -1 1 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2807, '25 1 18 1 -1 1 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2808, '25 1 18 1 22 -1 1 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2809, '25 22 22 -1 1 2 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2810, '25 22 22 22 -1 1 2 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2811, '25 22 22 1 -1 1 2 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2812, '25 22 22 1 22 -1 1 2 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2813, '25 22 15 -1 1 2 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2814, '25 22 15 22 -1 1 2 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2815, '25 22 18 18 1 -1 1 2 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2816, '25 22 18 18 1 22 -1 1 2 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2817, '25 22 18 1 -1 1 2 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2818, '25 22 18 1 22 -1 1 2 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2819, '25 22 2 -1 1 2 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2820, '25 22 2 22 -1 1 2 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2821, '25 22 1 13 1 -1 1 2 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2822, '25 22 1 13 1 22 -1 1 2 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2823, '25 22 1 18 -1 1 2 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2824, '25 22 1 18 22 -1 1 2 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2825, '25 22 1 18 1 -1 1 2 5 5 5 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2826, '25 22 1 18 1 22 -1 1 2 5 5 5 7 -1 1 5');
INSERT INTO pagc_rules (id, rule) VALUES (2827, '0 2 1 18 -1 1 4 5 5 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (2828, '0 2 1 18 22 -1 1 4 5 5 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (2829, '0 2 1 18 1 -1 1 4 5 5 5 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (2830, '0 2 1 18 1 22 -1 1 4 5 5 5 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (2831, '0 2 0 18 -1 1 4 5 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2832, '0 2 0 18 22 -1 1 4 5 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2833, '0 2 0 1 -1 1 4 5 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2834, '0 2 0 1 22 -1 1 4 5 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2835, '0 2 18 1 -1 1 4 5 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2836, '0 2 18 1 22 -1 1 4 5 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2837, '0 2 18 18 1 -1 1 4 5 5 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2838, '0 2 18 18 1 22 -1 1 4 5 5 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2839, '0 18 2 1 18 -1 1 1 4 5 5 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (2840, '0 18 2 1 18 22 -1 1 1 4 5 5 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (2841, '0 18 2 1 18 1 -1 1 1 4 5 5 5 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (2842, '0 18 2 1 18 1 22 -1 1 1 4 5 5 5 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (2843, '0 18 2 0 18 -1 1 1 4 5 5 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (2844, '0 18 2 0 18 22 -1 1 1 4 5 5 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (2845, '0 18 2 0 1 -1 1 1 4 5 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2846, '0 18 2 0 1 22 -1 1 1 4 5 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2847, '0 18 2 18 1 -1 1 1 4 5 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2848, '0 18 2 18 1 22 -1 1 1 4 5 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2849, '0 18 2 18 18 1 -1 1 1 4 5 5 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2850, '0 18 2 18 18 1 22 -1 1 1 4 5 5 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2851, '0 25 2 1 18 -1 1 1 4 5 5 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (2852, '0 25 2 1 18 22 -1 1 1 4 5 5 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (2853, '0 25 2 1 18 1 -1 1 1 4 5 5 5 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (2854, '0 25 2 1 18 1 22 -1 1 1 4 5 5 5 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (2855, '0 25 2 0 18 -1 1 1 4 5 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2856, '0 25 2 0 18 22 -1 1 1 4 5 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2857, '0 25 2 0 1 -1 1 1 4 5 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2858, '0 25 2 0 1 22 -1 1 1 4 5 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2859, '0 25 2 18 1 -1 1 1 4 5 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2860, '0 25 2 18 1 22 -1 1 1 4 5 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2861, '0 25 2 18 18 1 -1 1 1 4 5 5 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2862, '0 25 2 18 18 1 22 -1 1 1 4 5 5 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2863, '25 2 1 18 -1 1 4 5 5 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (2864, '25 2 1 18 22 -1 1 4 5 5 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (2865, '25 2 1 18 1 -1 1 4 5 5 5 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (2866, '25 2 1 18 1 22 -1 1 4 5 5 5 7 -1 1 11');
INSERT INTO pagc_rules (id, rule) VALUES (2867, '25 2 0 18 -1 1 4 5 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2868, '25 2 0 18 22 -1 1 4 5 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2869, '25 2 0 1 -1 1 4 5 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2870, '25 2 0 1 22 -1 1 4 5 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2871, '25 2 18 1 -1 1 4 5 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2872, '25 2 18 1 22 -1 1 4 5 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2873, '25 2 18 18 1 -1 1 4 5 5 5 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2874, '25 2 18 18 1 22 -1 1 4 5 5 5 7 -1 1 8');
INSERT INTO pagc_rules (id, rule) VALUES (2875, '0 14 2 -1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2876, '0 14 2 22 -1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2877, '0 15 1 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2878, '0 15 1 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2879, '0 24 2 -1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2880, '0 24 2 22 -1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2881, '0 24 24 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2882, '0 24 24 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2883, '0 24 2 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2884, '0 24 2 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2885, '0 24 1 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2886, '0 24 1 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2887, '0 22 2 -1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2888, '0 22 2 22 -1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2889, '0 22 1 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2890, '0 22 1 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2891, '0 25 2 -1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2892, '0 25 2 22 -1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2893, '0 0 25 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2894, '0 0 25 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2895, '0 15 2 -1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2896, '0 15 2 22 -1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2897, '0 18 18 18 2 -1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2898, '0 18 18 18 2 22 -1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2899, '0 18 18 1 2 -1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2900, '0 18 18 1 2 22 -1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2901, '0 18 2 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2902, '0 18 2 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2903, '0 18 1 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2904, '0 18 1 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2905, '0 2 2 -1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2906, '0 2 2 22 -1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2907, '0 2 0 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2908, '0 2 0 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2909, '0 2 1 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2910, '0 2 1 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2911, '0 16 0 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2912, '0 16 0 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2913, '0 1 13 1 2 -1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2914, '0 1 13 1 2 22 -1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2915, '0 1 15 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2916, '0 1 15 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2917, '0 1 24 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2918, '0 1 24 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2919, '0 1 24 24 2 -1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2920, '0 1 24 24 2 22 -1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2921, '0 1 24 1 2 -1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2922, '0 1 24 1 2 22 -1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2923, '0 1 22 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2924, '0 1 22 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2925, '0 1 22 1 2 -1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2926, '0 1 22 1 2 22 -1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2927, '0 1 25 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2928, '0 1 25 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2929, '0 1 0 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2930, '0 1 0 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2931, '0 1 18 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2932, '0 1 18 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2933, '0 1 18 2 2 -1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2934, '0 1 18 2 2 22 -1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2935, '0 1 18 1 2 -1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2936, '0 1 18 1 2 22 -1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2937, '0 1 2 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2938, '0 1 2 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2939, '0 1 2 2 2 -1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2940, '0 1 2 2 2 22 -1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2941, '0 21 2 -1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2942, '0 21 2 22 -1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2943, '0 22 14 2 -1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2944, '0 22 14 2 22 -1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2945, '0 22 15 1 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2946, '0 22 15 1 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2947, '0 22 24 2 -1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2948, '0 22 24 2 22 -1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2949, '0 22 24 24 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2950, '0 22 24 24 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2951, '0 22 24 2 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2952, '0 22 24 2 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2953, '0 22 24 1 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2954, '0 22 24 1 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2955, '0 22 22 2 -1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2956, '0 22 22 2 22 -1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2957, '0 22 22 1 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2958, '0 22 22 1 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2959, '0 22 25 2 -1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2960, '0 22 25 2 22 -1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2961, '0 22 0 25 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2962, '0 22 0 25 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2963, '0 22 15 2 -1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2964, '0 22 15 2 22 -1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2965, '0 22 18 18 18 2 -1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2966, '0 22 18 18 18 2 22 -1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2967, '0 22 18 18 1 2 -1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2968, '0 22 18 18 1 2 22 -1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2969, '0 22 18 2 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2970, '0 22 18 2 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2971, '0 22 18 1 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2972, '0 22 18 1 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2973, '0 22 2 2 -1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2974, '0 22 2 2 22 -1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2975, '0 22 2 0 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2976, '0 22 2 0 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2977, '0 22 2 1 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2978, '0 22 2 1 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2979, '0 22 16 0 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2980, '0 22 16 0 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2981, '0 22 1 13 1 2 -1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2982, '0 22 1 13 1 2 22 -1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2983, '0 22 1 15 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2984, '0 22 1 15 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2985, '0 22 1 24 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2986, '0 22 1 24 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2987, '0 22 1 24 24 2 -1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2988, '0 22 1 24 24 2 22 -1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2989, '0 22 1 24 1 2 -1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2990, '0 22 1 24 1 2 22 -1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2991, '0 22 1 22 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2992, '0 22 1 22 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2993, '0 22 1 22 1 2 -1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2994, '0 22 1 22 1 2 22 -1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2995, '0 22 1 25 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2996, '0 22 1 25 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2997, '0 22 1 0 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2998, '0 22 1 0 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (2999, '0 22 1 18 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3000, '0 22 1 18 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3001, '0 22 1 18 2 2 -1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3002, '0 22 1 18 2 2 22 -1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3003, '0 22 1 18 1 2 -1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3004, '0 22 1 18 1 2 22 -1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3005, '0 22 1 2 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3006, '0 22 1 2 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3007, '0 22 1 2 2 2 -1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3008, '0 22 1 2 2 2 22 -1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3009, '0 22 21 2 -1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3010, '0 22 21 2 22 -1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3011, '0 18 14 2 -1 1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3012, '0 18 14 2 22 -1 1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3013, '0 18 15 1 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3014, '0 18 15 1 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3015, '0 18 24 2 -1 1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3016, '0 18 24 2 22 -1 1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3017, '0 18 24 24 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3018, '0 18 24 24 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3019, '0 18 24 2 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3020, '0 18 24 2 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3021, '0 18 24 1 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3022, '0 18 24 1 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3023, '0 18 22 2 -1 1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3024, '0 18 22 2 22 -1 1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3025, '0 18 22 1 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3026, '0 18 22 1 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3027, '0 18 25 2 -1 1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3028, '0 18 25 2 22 -1 1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3029, '0 18 0 25 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3030, '0 18 0 25 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3031, '0 18 15 2 -1 1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3032, '0 18 15 2 22 -1 1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3033, '0 18 18 18 18 2 -1 1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3034, '0 18 18 18 18 2 22 -1 1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3035, '0 18 18 18 1 2 -1 1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3036, '0 18 18 18 1 2 22 -1 1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3037, '0 18 18 2 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3038, '0 18 18 2 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3039, '0 18 18 1 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3040, '0 18 18 1 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3041, '0 18 2 2 -1 1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3042, '0 18 2 2 22 -1 1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3043, '0 18 2 0 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3044, '0 18 2 0 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3045, '0 18 2 1 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3046, '0 18 2 1 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3047, '0 18 16 0 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3048, '0 18 16 0 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3049, '0 18 1 13 1 2 -1 1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3050, '0 18 1 13 1 2 22 -1 1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3051, '0 18 1 15 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3052, '0 18 1 15 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3053, '0 18 1 24 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3054, '0 18 1 24 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3055, '0 18 1 24 24 2 -1 1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3056, '0 18 1 24 24 2 22 -1 1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3057, '0 18 1 24 1 2 -1 1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3058, '0 18 1 24 1 2 22 -1 1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3059, '0 18 1 22 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3060, '0 18 1 22 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3061, '0 18 1 22 1 2 -1 1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3062, '0 18 1 22 1 2 22 -1 1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3063, '0 18 1 25 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3064, '0 18 1 25 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3065, '0 18 1 0 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3066, '0 18 1 0 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3067, '0 18 1 18 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3068, '0 18 1 18 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3069, '0 18 1 18 2 2 -1 1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3070, '0 18 1 18 2 2 22 -1 1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3071, '0 18 1 18 1 2 -1 1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3072, '0 18 1 18 1 2 22 -1 1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3073, '0 18 1 2 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3074, '0 18 1 2 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3075, '0 18 1 2 2 2 -1 1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3076, '0 18 1 2 2 2 22 -1 1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3077, '0 18 21 2 -1 1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3078, '0 18 21 2 22 -1 1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3079, '0 18 22 14 2 -1 1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3080, '0 18 22 14 2 22 -1 1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3081, '0 18 22 15 1 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3082, '0 18 22 15 1 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3083, '0 18 22 24 2 -1 1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3084, '0 18 22 24 2 22 -1 1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3085, '0 18 22 24 24 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3086, '0 18 22 24 24 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3087, '0 18 22 24 2 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3088, '0 18 22 24 2 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3089, '0 18 22 24 1 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3090, '0 18 22 24 1 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3091, '0 18 22 22 2 -1 1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3092, '0 18 22 22 2 22 -1 1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3093, '0 18 22 22 1 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3094, '0 18 22 22 1 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3095, '0 18 22 25 2 -1 1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3096, '0 18 22 25 2 22 -1 1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3097, '0 18 22 0 25 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3098, '0 18 22 0 25 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3099, '0 18 22 15 2 -1 1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3100, '0 18 22 15 2 22 -1 1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3101, '0 18 22 18 18 18 2 -1 1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3102, '0 18 22 18 18 18 2 22 -1 1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3103, '0 18 22 18 18 1 2 -1 1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3104, '0 18 22 18 18 1 2 22 -1 1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3105, '0 18 22 18 2 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3106, '0 18 22 18 2 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3107, '0 18 22 18 1 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3108, '0 18 22 18 1 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3109, '0 18 22 2 2 -1 1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3110, '0 18 22 2 2 22 -1 1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3111, '0 18 22 2 0 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3112, '0 18 22 2 0 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3113, '0 18 22 2 1 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3114, '0 18 22 2 1 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3115, '0 18 22 16 0 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3116, '0 18 22 16 0 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3117, '0 18 22 1 13 1 2 -1 1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3118, '0 18 22 1 13 1 2 22 -1 1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3119, '0 18 22 1 15 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3120, '0 18 22 1 15 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3121, '0 18 22 1 24 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3122, '0 18 22 1 24 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3123, '0 18 22 1 24 24 2 -1 1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3124, '0 18 22 1 24 24 2 22 -1 1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3125, '0 18 22 1 24 1 2 -1 1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3126, '0 18 22 1 24 1 2 22 -1 1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3127, '0 18 22 1 22 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3128, '0 18 22 1 22 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3129, '0 18 22 1 22 1 2 -1 1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3130, '0 18 22 1 22 1 2 22 -1 1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3131, '0 18 22 1 25 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3132, '0 18 22 1 25 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3133, '0 18 22 1 0 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3134, '0 18 22 1 0 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3135, '0 18 22 1 18 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3136, '0 18 22 1 18 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3137, '0 18 22 1 18 2 2 -1 1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3138, '0 18 22 1 18 2 2 22 -1 1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3139, '0 18 22 1 18 1 2 -1 1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3140, '0 18 22 1 18 1 2 22 -1 1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3141, '0 18 22 1 2 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3142, '0 18 22 1 2 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3143, '0 18 22 1 2 2 2 -1 1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3144, '0 18 22 1 2 2 2 22 -1 1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3145, '0 18 22 21 2 -1 1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3146, '0 18 22 21 2 22 -1 1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3147, '0 25 14 2 -1 1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3148, '0 25 14 2 22 -1 1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3149, '0 25 15 1 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3150, '0 25 15 1 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3151, '0 25 24 2 -1 1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3152, '0 25 24 2 22 -1 1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3153, '0 25 24 24 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3154, '0 25 24 24 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3155, '0 25 24 2 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3156, '0 25 24 2 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3157, '0 25 24 1 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3158, '0 25 24 1 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3159, '0 25 22 2 -1 1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3160, '0 25 22 2 22 -1 1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3161, '0 25 22 1 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3162, '0 25 22 1 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3163, '0 25 25 2 -1 1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3164, '0 25 25 2 22 -1 1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3165, '0 25 0 25 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3166, '0 25 0 25 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3167, '0 25 15 2 -1 1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3168, '0 25 15 2 22 -1 1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3169, '0 25 18 18 18 2 -1 1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3170, '0 25 18 18 18 2 22 -1 1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3171, '0 25 18 18 1 2 -1 1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3172, '0 25 18 18 1 2 22 -1 1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3173, '0 25 18 2 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3174, '0 25 18 2 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3175, '0 25 18 1 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3176, '0 25 18 1 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3177, '0 25 2 2 -1 1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3178, '0 25 2 2 22 -1 1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3179, '0 25 2 0 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3180, '0 25 2 0 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3181, '0 25 2 1 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3182, '0 25 2 1 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3183, '0 25 16 0 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3184, '0 25 16 0 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3185, '0 25 1 13 1 2 -1 1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3186, '0 25 1 13 1 2 22 -1 1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3187, '0 25 1 15 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3188, '0 25 1 15 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3189, '0 25 1 24 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3190, '0 25 1 24 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3191, '0 25 1 24 24 2 -1 1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3192, '0 25 1 24 24 2 22 -1 1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3193, '0 25 1 24 1 2 -1 1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3194, '0 25 1 24 1 2 22 -1 1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3195, '0 25 1 22 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3196, '0 25 1 22 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3197, '0 25 1 22 1 2 -1 1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3198, '0 25 1 22 1 2 22 -1 1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3199, '0 25 1 25 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3200, '0 25 1 25 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3201, '0 25 1 0 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3202, '0 25 1 0 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3203, '0 25 1 18 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3204, '0 25 1 18 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3205, '0 25 1 18 2 2 -1 1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3206, '0 25 1 18 2 2 22 -1 1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3207, '0 25 1 18 1 2 -1 1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3208, '0 25 1 18 1 2 22 -1 1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3209, '0 25 1 2 2 -1 1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3210, '0 25 1 2 2 22 -1 1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3211, '0 25 1 2 2 2 -1 1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3212, '0 25 1 2 2 2 22 -1 1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3213, '0 25 21 2 -1 1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3214, '0 25 21 2 22 -1 1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3215, '0 25 22 14 2 -1 1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3216, '0 25 22 14 2 22 -1 1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3217, '0 25 22 15 1 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3218, '0 25 22 15 1 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3219, '0 25 22 24 2 -1 1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3220, '0 25 22 24 2 22 -1 1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3221, '0 25 22 24 24 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3222, '0 25 22 24 24 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3223, '0 25 22 24 2 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3224, '0 25 22 24 2 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3225, '0 25 22 24 1 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3226, '0 25 22 24 1 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3227, '0 25 22 22 2 -1 1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3228, '0 25 22 22 2 22 -1 1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3229, '0 25 22 22 1 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3230, '0 25 22 22 1 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3231, '0 25 22 25 2 -1 1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3232, '0 25 22 25 2 22 -1 1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3233, '0 25 22 0 25 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3234, '0 25 22 0 25 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3235, '0 25 22 15 2 -1 1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3236, '0 25 22 15 2 22 -1 1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3237, '0 25 22 18 18 18 2 -1 1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3238, '0 25 22 18 18 18 2 22 -1 1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3239, '0 25 22 18 18 1 2 -1 1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3240, '0 25 22 18 18 1 2 22 -1 1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3241, '0 25 22 18 2 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3242, '0 25 22 18 2 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3243, '0 25 22 18 1 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3244, '0 25 22 18 1 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3245, '0 25 22 2 2 -1 1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3246, '0 25 22 2 2 22 -1 1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3247, '0 25 22 2 0 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3248, '0 25 22 2 0 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3249, '0 25 22 2 1 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3250, '0 25 22 2 1 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3251, '0 25 22 16 0 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3252, '0 25 22 16 0 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3253, '0 25 22 1 13 1 2 -1 1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3254, '0 25 22 1 13 1 2 22 -1 1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3255, '0 25 22 1 15 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3256, '0 25 22 1 15 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3257, '0 25 22 1 24 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3258, '0 25 22 1 24 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3259, '0 25 22 1 24 24 2 -1 1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3260, '0 25 22 1 24 24 2 22 -1 1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3261, '0 25 22 1 24 1 2 -1 1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3262, '0 25 22 1 24 1 2 22 -1 1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3263, '0 25 22 1 22 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3264, '0 25 22 1 22 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3265, '0 25 22 1 22 1 2 -1 1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3266, '0 25 22 1 22 1 2 22 -1 1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3267, '0 25 22 1 25 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3268, '0 25 22 1 25 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3269, '0 25 22 1 0 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3270, '0 25 22 1 0 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3271, '0 25 22 1 18 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3272, '0 25 22 1 18 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3273, '0 25 22 1 18 2 2 -1 1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3274, '0 25 22 1 18 2 2 22 -1 1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3275, '0 25 22 1 18 1 2 -1 1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3276, '0 25 22 1 18 1 2 22 -1 1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3277, '0 25 22 1 2 2 -1 1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3278, '0 25 22 1 2 2 22 -1 1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3279, '0 25 22 1 2 2 2 -1 1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3280, '0 25 22 1 2 2 2 22 -1 1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3281, '0 25 22 21 2 -1 1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3282, '0 25 22 21 2 22 -1 1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3283, '25 14 2 -1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3284, '25 14 2 22 -1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3285, '25 15 1 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3286, '25 15 1 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3287, '25 24 2 -1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3288, '25 24 2 22 -1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3289, '25 24 24 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3290, '25 24 24 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3291, '25 24 2 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3292, '25 24 2 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3293, '25 24 1 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3294, '25 24 1 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3295, '25 22 2 -1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3296, '25 22 2 22 -1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3297, '25 22 1 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3298, '25 22 1 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3299, '25 25 2 -1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3300, '25 25 2 22 -1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3301, '25 0 25 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3302, '25 0 25 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3303, '25 15 2 -1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3304, '25 15 2 22 -1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3305, '25 18 18 18 2 -1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3306, '25 18 18 18 2 22 -1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3307, '25 18 18 1 2 -1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3308, '25 18 18 1 2 22 -1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3309, '25 18 2 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3310, '25 18 2 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3311, '25 18 1 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3312, '25 18 1 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3313, '25 2 2 -1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3314, '25 2 2 22 -1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3315, '25 2 0 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3316, '25 2 0 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3317, '25 2 1 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3318, '25 2 1 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3319, '25 16 0 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3320, '25 16 0 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3321, '25 1 13 1 2 -1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3322, '25 1 13 1 2 22 -1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3323, '25 1 15 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3324, '25 1 15 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3325, '25 1 24 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3326, '25 1 24 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3327, '25 1 24 24 2 -1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3328, '25 1 24 24 2 22 -1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3329, '25 1 24 1 2 -1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3330, '25 1 24 1 2 22 -1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3331, '25 1 22 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3332, '25 1 22 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3333, '25 1 22 1 2 -1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3334, '25 1 22 1 2 22 -1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3335, '25 1 25 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3336, '25 1 25 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3337, '25 1 0 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3338, '25 1 0 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3339, '25 1 18 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3340, '25 1 18 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3341, '25 1 18 2 2 -1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3342, '25 1 18 2 2 22 -1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3343, '25 1 18 1 2 -1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3344, '25 1 18 1 2 22 -1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3345, '25 1 2 2 -1 1 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3346, '25 1 2 2 22 -1 1 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3347, '25 1 2 2 2 -1 1 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3348, '25 1 2 2 2 22 -1 1 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3349, '25 21 2 -1 1 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3350, '25 21 2 22 -1 1 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3351, '25 22 14 2 -1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3352, '25 22 14 2 22 -1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3353, '25 22 15 1 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3354, '25 22 15 1 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3355, '25 22 24 2 -1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3356, '25 22 24 2 22 -1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3357, '25 22 24 24 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3358, '25 22 24 24 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3359, '25 22 24 2 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3360, '25 22 24 2 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3361, '25 22 24 1 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3362, '25 22 24 1 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3363, '25 22 22 2 -1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3364, '25 22 22 2 22 -1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3365, '25 22 22 1 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3366, '25 22 22 1 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3367, '25 22 25 2 -1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3368, '25 22 25 2 22 -1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3369, '25 22 0 25 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3370, '25 22 0 25 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3371, '25 22 15 2 -1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3372, '25 22 15 2 22 -1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3373, '25 22 18 18 18 2 -1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3374, '25 22 18 18 18 2 22 -1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3375, '25 22 18 18 1 2 -1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3376, '25 22 18 18 1 2 22 -1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3377, '25 22 18 2 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3378, '25 22 18 2 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3379, '25 22 18 1 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3380, '25 22 18 1 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3381, '25 22 2 2 -1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3382, '25 22 2 2 22 -1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3383, '25 22 2 0 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3384, '25 22 2 0 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3385, '25 22 2 1 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3386, '25 22 2 1 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3387, '25 22 16 0 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3388, '25 22 16 0 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3389, '25 22 1 13 1 2 -1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3390, '25 22 1 13 1 2 22 -1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3391, '25 22 1 15 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3392, '25 22 1 15 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3393, '25 22 1 24 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3394, '25 22 1 24 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3395, '25 22 1 24 24 2 -1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3396, '25 22 1 24 24 2 22 -1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3397, '25 22 1 24 1 2 -1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3398, '25 22 1 24 1 2 22 -1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3399, '25 22 1 22 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3400, '25 22 1 22 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3401, '25 22 1 22 1 2 -1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3402, '25 22 1 22 1 2 22 -1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3403, '25 22 1 25 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3404, '25 22 1 25 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3405, '25 22 1 0 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3406, '25 22 1 0 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3407, '25 22 1 18 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3408, '25 22 1 18 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3409, '25 22 1 18 2 2 -1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3410, '25 22 1 18 2 2 22 -1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3411, '25 22 1 18 1 2 -1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3412, '25 22 1 18 1 2 22 -1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3413, '25 22 1 2 2 -1 1 2 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3414, '25 22 1 2 2 22 -1 1 2 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3415, '25 22 1 2 2 2 -1 1 2 5 5 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3416, '25 22 1 2 2 2 22 -1 1 2 5 5 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3417, '25 22 21 2 -1 1 2 5 6 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3418, '25 22 21 2 22 -1 1 2 5 6 7 -1 1 16');
INSERT INTO pagc_rules (id, rule) VALUES (3419, '0 -1 1 -1 3 17');
INSERT INTO pagc_rules (id, rule) VALUES (3420, '0 18 -1 1 1 -1 3 16');
INSERT INTO pagc_rules (id, rule) VALUES (3421, '0 25 -1 1 1 -1 3 16');
INSERT INTO pagc_rules (id, rule) VALUES (3422, '0 22 -1 1 1 -1 3 9');
INSERT INTO pagc_rules (id, rule) VALUES (3423, '22 0 -1 1 1 -1 3 9');
INSERT INTO pagc_rules (id, rule) VALUES (3424, '1 0 -1 1 1 -1 3 6');
INSERT INTO pagc_rules (id, rule) VALUES (3425, '18 0 -1 1 1 -1 3 12');
INSERT INTO pagc_rules (id, rule) VALUES (3426, '25 -1 1 -1 3 12');
INSERT INTO pagc_rules (id, rule) VALUES (3427, '21 0 -1 1 1 -1 3 12');
INSERT INTO pagc_rules (id, rule) VALUES (3428, '0 21 -1 1 1 -1 3 9');
INSERT INTO pagc_rules (id, rule) VALUES (3429, '0 0 -1 1 1 -1 3 15');
INSERT INTO pagc_rules (id, rule) VALUES (3430, '21 0 0 -1 1 1 1 -1 3 9');
INSERT INTO pagc_rules (id, rule) VALUES (3431, '0 0 21 -1 1 1 1 -1 3 9');
INSERT INTO pagc_rules (id, rule) VALUES (3432, '0 0 18 -1 1 1 1 -1 3 9');
INSERT INTO pagc_rules (id, rule) VALUES (3433, '18 0 -1 1 1 -1 3 9');
INSERT INTO pagc_rules (id, rule) VALUES (3434, '18 0 0 -1 1 1 1 -1 3 9');
INSERT INTO pagc_rules (id, rule) VALUES (3435, '0 0 18 -1 1 1 1 -1 3 9');
INSERT INTO pagc_rules (id, rule) VALUES (3436, '8 -1 8 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3437, '8 23 -1 8 8 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3438, '8 0 -1 8 8 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3439, '8 0 18 -1 8 8 8 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3440, '8 18 -1 8 8 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3441, '8 18 0 -1 8 8 8 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3442, '8 1 -1 8 8 -1 4 2');
INSERT INTO pagc_rules (id, rule) VALUES (3443, '14 -1 14 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3444, '14 21 -1 14 15 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3445, '14 23 -1 14 15 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3446, '14 0 -1 14 15 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3447, '14 0 18 -1 14 15 15 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3448, '14 0 18 0 -1 14 15 15 15 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3449, '14 18 -1 14 15 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3450, '14 18 0 -1 14 15 15 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3451, '14 1 -1 14 15 -1 4 2');
INSERT INTO pagc_rules (id, rule) VALUES (3452, '1 24 -1 0 0 -1 4 15');
INSERT INTO pagc_rules (id, rule) VALUES (3453, '14 24 -1 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3454, '24 24 -1 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3455, '24 24 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3456, '24 22 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3457, '24 18 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3458, '24 2 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3459, '24 1 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3460, '22 24 -1 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3461, '22 24 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3462, '22 24 24 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3463, '22 24 1 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3464, '22 22 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3465, '22 2 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3466, '22 1 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3467, '18 24 -1 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3468, '18 13 18 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3469, '18 24 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3470, '18 18 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3471, '18 18 18 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3472, '18 18 2 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3473, '18 18 1 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3474, '18 2 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3475, '18 1 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3476, '18 1 24 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3477, '2 24 -1 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3478, '2 22 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3479, '2 0 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3480, '2 18 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3481, '2 2 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3482, '2 1 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3483, '1 13 1 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3484, '1 24 24 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3485, '1 24 22 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3486, '1 24 2 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3487, '1 24 1 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3488, '1 22 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3489, '1 22 24 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3490, '1 0 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3491, '1 0 24 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3492, '1 0 1 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3493, '1 18 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3494, '1 18 1 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3495, '1 2 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3496, '1 2 1 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3497, '0 1 24 -1 0 0 0 -1 4 15');
INSERT INTO pagc_rules (id, rule) VALUES (3498, '0 14 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3499, '0 24 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3500, '0 24 24 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3501, '0 24 22 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3502, '0 24 18 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3503, '0 24 2 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3504, '0 24 1 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3505, '0 22 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3506, '0 22 24 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3507, '0 22 24 24 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3508, '0 22 24 1 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3509, '0 22 22 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3510, '0 22 2 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3511, '0 22 1 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3512, '0 18 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3513, '0 18 13 18 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3514, '0 18 24 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3515, '0 18 18 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3516, '0 18 18 18 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3517, '0 18 18 2 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3518, '0 18 18 1 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3519, '0 18 2 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3520, '0 18 1 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3521, '0 18 1 24 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3522, '0 2 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3523, '0 2 22 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3524, '0 2 0 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3525, '0 2 18 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3526, '0 2 2 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3527, '0 2 1 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3528, '0 1 13 1 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3529, '0 1 24 24 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3530, '0 1 24 22 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3531, '0 1 24 2 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3532, '0 1 24 1 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3533, '0 1 22 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3534, '0 1 22 24 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3535, '0 1 0 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3536, '0 1 0 24 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3537, '0 1 0 1 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3538, '0 1 18 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3539, '0 1 18 1 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3540, '0 1 2 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3541, '0 1 2 1 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3542, '0 18 1 24 -1 0 0 0 0 -1 4 15');
INSERT INTO pagc_rules (id, rule) VALUES (3543, '0 18 14 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3544, '0 18 24 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3545, '0 18 24 24 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3546, '0 18 24 22 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3547, '0 18 24 18 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3548, '0 18 24 2 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3549, '0 18 24 1 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3550, '0 18 22 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3551, '0 18 22 24 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3552, '0 18 22 24 24 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3553, '0 18 22 24 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3554, '0 18 22 22 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3555, '0 18 22 2 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3556, '0 18 22 1 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3557, '0 18 18 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3558, '0 18 18 13 18 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3559, '0 18 18 24 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3560, '0 18 18 18 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3561, '0 18 18 18 18 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3562, '0 18 18 18 2 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3563, '0 18 18 18 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3564, '0 18 18 2 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3565, '0 18 18 1 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3566, '0 18 18 1 24 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3567, '0 18 2 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3568, '0 18 2 22 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3569, '0 18 2 0 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3570, '0 18 2 18 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3571, '0 18 2 2 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3572, '0 18 2 1 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3573, '0 18 1 13 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3574, '0 18 1 24 24 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3575, '0 18 1 24 22 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3576, '0 18 1 24 2 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3577, '0 18 1 24 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3578, '0 18 1 22 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3579, '0 18 1 22 24 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3580, '0 18 1 0 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3581, '0 18 1 0 24 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3582, '0 18 1 0 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3583, '0 18 1 18 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3584, '0 18 1 18 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3585, '0 18 1 2 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3586, '0 18 1 2 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3587, '0 25 1 24 -1 0 0 0 0 -1 4 15');
INSERT INTO pagc_rules (id, rule) VALUES (3588, '0 25 14 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3589, '0 25 24 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3590, '0 25 24 24 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3591, '0 25 24 22 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3592, '0 25 24 18 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3593, '0 25 24 2 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3594, '0 25 24 1 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3595, '0 25 22 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3596, '0 25 22 24 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3597, '0 25 22 24 24 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3598, '0 25 22 24 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3599, '0 25 22 22 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3600, '0 25 22 2 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3601, '0 25 22 1 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3602, '0 25 18 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3603, '0 25 18 13 18 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3604, '0 25 18 24 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3605, '0 25 18 18 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3606, '0 25 18 18 18 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3607, '0 25 18 18 2 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3608, '0 25 18 18 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3609, '0 25 18 2 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3610, '0 25 18 1 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3611, '0 25 18 1 24 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3612, '0 25 2 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3613, '0 25 2 22 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3614, '0 25 2 0 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3615, '0 25 2 18 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3616, '0 25 2 2 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3617, '0 25 2 1 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3618, '0 25 1 13 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3619, '0 25 1 24 24 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3620, '0 25 1 24 22 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3621, '0 25 1 24 2 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3622, '0 25 1 24 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3623, '0 25 1 22 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3624, '0 25 1 22 24 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3625, '0 25 1 0 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3626, '0 25 1 0 24 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3627, '0 25 1 0 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3628, '0 25 1 18 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3629, '0 25 1 18 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3630, '0 25 1 2 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3631, '0 25 1 2 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3632, '18 0 1 24 -1 0 0 0 0 -1 4 15');
INSERT INTO pagc_rules (id, rule) VALUES (3633, '18 0 14 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3634, '18 0 24 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3635, '18 0 24 24 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3636, '18 0 24 22 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3637, '18 0 24 18 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3638, '18 0 24 2 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3639, '18 0 24 1 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3640, '18 0 22 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3641, '18 0 22 24 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3642, '18 0 22 24 24 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3643, '18 0 22 24 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3644, '18 0 22 22 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3645, '18 0 22 2 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3646, '18 0 22 1 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3647, '18 0 18 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3648, '18 0 18 13 18 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3649, '18 0 18 24 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3650, '18 0 18 18 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3651, '18 0 18 18 18 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3652, '18 0 18 18 2 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3653, '18 0 18 18 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3654, '18 0 18 2 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3655, '18 0 18 1 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3656, '18 0 18 1 24 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3657, '18 0 2 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3658, '18 0 2 22 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3659, '18 0 2 0 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3660, '18 0 2 18 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3661, '18 0 2 2 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3662, '18 0 2 1 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3663, '18 0 1 13 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3664, '18 0 1 24 24 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3665, '18 0 1 24 22 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3666, '18 0 1 24 2 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3667, '18 0 1 24 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3668, '18 0 1 22 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3669, '18 0 1 22 24 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3670, '18 0 1 0 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3671, '18 0 1 0 24 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3672, '18 0 1 0 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3673, '18 0 1 18 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3674, '18 0 1 18 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3675, '18 0 1 2 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3676, '18 0 1 2 1 24 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3677, '19 -1 0 -1 4 2');
INSERT INTO pagc_rules (id, rule) VALUES (3678, '19 1 -1 0 0 -1 4 6');
INSERT INTO pagc_rules (id, rule) VALUES (3679, '19 24 1 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3680, '19 24 1 0 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3681, '19 23 -1 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3682, '19 0 -1 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3683, '19 0 24 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3684, '19 0 1 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3685, '19 18 -1 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3686, '19 2 0 -1 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3687, '19 1 0 -1 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3688, '0 19 -1 0 0 -1 4 2');
INSERT INTO pagc_rules (id, rule) VALUES (3689, '0 19 1 -1 0 0 0 -1 4 6');
INSERT INTO pagc_rules (id, rule) VALUES (3690, '0 19 24 1 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3691, '0 19 24 1 0 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3692, '0 19 23 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3693, '0 19 0 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3694, '0 19 0 24 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3695, '0 19 0 1 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3696, '0 19 18 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3697, '0 19 2 0 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3698, '0 19 1 0 -1 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3699, '0 18 19 -1 0 0 0 -1 4 2');
INSERT INTO pagc_rules (id, rule) VALUES (3700, '0 18 19 1 -1 0 0 0 0 -1 4 6');
INSERT INTO pagc_rules (id, rule) VALUES (3701, '0 18 19 24 1 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3702, '0 18 19 24 1 0 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3703, '0 18 19 23 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3704, '0 18 19 0 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3705, '0 18 19 0 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3706, '0 18 19 0 1 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3707, '0 18 19 18 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3708, '0 18 19 2 0 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3709, '0 18 19 1 0 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3710, '0 25 19 -1 0 0 0 -1 4 2');
INSERT INTO pagc_rules (id, rule) VALUES (3711, '0 25 19 1 -1 0 0 0 0 -1 4 6');
INSERT INTO pagc_rules (id, rule) VALUES (3712, '0 25 19 24 1 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3713, '0 25 19 24 1 0 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3714, '0 25 19 23 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3715, '0 25 19 0 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3716, '0 25 19 0 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3717, '0 25 19 0 1 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3718, '0 25 19 18 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3719, '0 25 19 2 0 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3720, '0 25 19 1 0 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3721, '18 0 19 -1 0 0 0 -1 4 2');
INSERT INTO pagc_rules (id, rule) VALUES (3722, '18 0 19 1 -1 0 0 0 0 -1 4 6');
INSERT INTO pagc_rules (id, rule) VALUES (3723, '18 0 19 24 1 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3724, '18 0 19 24 1 0 -1 0 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3725, '18 0 19 23 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3726, '18 0 19 0 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3727, '18 0 19 0 24 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3728, '18 0 19 0 1 -1 0 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3729, '18 0 19 18 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3730, '18 0 19 2 0 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3731, '18 0 19 1 0 -1 0 0 0 0 -1 4 10');
INSERT INTO pagc_rules (id, rule) VALUES (3732, '23 -1 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3733, '0 -1 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3734, '18 -1 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3735, '18 0 -1 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3736, '18 18 -1 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3737, '18 0 18 -1 17 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3738, '21 -1 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3739, '21 0 -1 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3740, '25 -1 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3741, '0 21 -1 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3742, '0 0 -1 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3743, '0 18 -1 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3744, '0 1 -1 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3745, '1 -1 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3746, '16 -1 16 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3747, '16 23 -1 16 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3748, '16 0 -1 16 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3749, '16 18 -1 16 17 -1 4 11');
INSERT INTO pagc_rules (id, rule) VALUES (3750, '16 18 0 -1 16 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3751, '16 18 18 -1 16 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3752, '16 18 0 18 -1 16 17 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3753, '16 21 -1 16 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3754, '16 21 0 -1 16 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3755, '16 25 -1 16 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3756, '16 0 21 -1 16 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3757, '16 0 0 -1 16 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3758, '16 0 18 -1 16 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3759, '16 0 1 -1 16 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3760, '16 1 -1 16 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3761, '16 16 -1 16 16 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3762, '16 16 23 -1 16 16 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3763, '16 16 0 -1 16 16 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3764, '16 16 18 -1 16 16 17 -1 4 11');
INSERT INTO pagc_rules (id, rule) VALUES (3765, '16 16 18 0 -1 16 16 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3766, '16 16 18 18 -1 16 16 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3767, '16 16 18 0 18 -1 16 16 17 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3768, '16 16 21 -1 16 16 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3769, '16 16 21 0 -1 16 16 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3770, '16 16 25 -1 16 16 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3771, '16 16 0 21 -1 16 16 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3772, '16 16 0 0 -1 16 16 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3773, '16 16 0 18 -1 16 16 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3774, '16 16 0 1 -1 16 16 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3775, '16 16 1 -1 16 16 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (3776, '17 -1 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3777, '17 23 -1 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3778, '17 0 -1 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3779, '17 18 -1 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3780, '17 18 0 -1 17 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3781, '17 18 18 -1 17 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3782, '17 18 0 18 -1 17 17 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3783, '17 21 -1 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3784, '17 21 0 -1 17 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3785, '17 25 -1 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3786, '17 0 21 -1 17 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3787, '17 0 0 -1 17 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3788, '17 0 18 -1 17 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3789, '17 0 1 -1 17 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3790, '17 1 -1 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3791, '17 16 -1 17 16 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3792, '17 16 23 -1 17 16 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3793, '17 16 0 -1 17 16 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3794, '17 16 18 -1 17 16 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3795, '17 16 18 0 -1 17 16 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3796, '17 16 18 18 -1 17 16 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3797, '17 16 18 0 18 -1 17 16 17 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3798, '17 16 21 -1 17 16 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3799, '17 16 21 0 -1 17 16 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3800, '17 16 25 -1 17 16 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3801, '17 16 0 21 -1 17 16 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3802, '17 16 0 0 -1 17 16 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3803, '17 16 0 18 -1 17 16 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3804, '17 16 0 1 -1 17 16 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3805, '17 16 1 -1 17 16 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3806, '17 16 16 -1 17 16 16 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3807, '17 16 16 23 -1 17 16 16 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3808, '17 16 16 0 -1 17 16 16 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3809, '17 16 16 18 -1 17 16 16 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3810, '17 16 16 18 0 -1 17 16 16 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3811, '17 16 16 18 18 -1 17 16 16 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3812, '17 16 16 18 0 18 -1 17 16 16 17 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3813, '17 16 16 21 -1 17 16 16 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3814, '17 16 16 21 0 -1 17 16 16 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3815, '17 16 16 25 -1 17 16 16 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3816, '17 16 16 0 21 -1 17 16 16 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3817, '17 16 16 0 0 -1 17 16 16 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3818, '17 16 16 0 18 -1 17 16 16 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3819, '17 16 16 0 1 -1 17 16 16 17 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3820, '17 16 16 1 -1 17 16 16 17 -1 4 17');
INSERT INTO pagc_rules (id, rule) VALUES (3821, '15 17 -1 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3822, '15 17 23 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3823, '15 17 0 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3824, '15 17 18 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3825, '15 17 18 0 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3826, '15 17 18 18 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3827, '15 17 18 0 18 -1 17 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3828, '15 17 21 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3829, '15 17 21 0 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3830, '15 17 25 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3831, '15 17 0 21 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3832, '15 17 0 0 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3833, '15 17 0 18 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3834, '15 17 0 1 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3835, '15 17 1 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3836, '15 17 16 -1 17 17 16 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3837, '15 17 16 23 -1 17 17 16 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3838, '15 17 16 0 -1 17 17 16 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3839, '15 17 16 18 -1 17 17 16 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3840, '15 17 16 18 0 -1 17 17 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3841, '15 17 16 18 18 -1 17 17 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3842, '15 17 16 18 0 18 -1 17 17 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3843, '15 17 16 21 -1 17 17 16 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3844, '15 17 16 21 0 -1 17 17 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3845, '15 17 16 25 -1 17 17 16 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3846, '15 17 16 0 21 -1 17 17 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3847, '15 17 16 0 0 -1 17 17 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3848, '15 17 16 0 18 -1 17 17 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3849, '15 17 16 0 1 -1 17 17 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3850, '15 17 16 1 -1 17 17 16 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3851, '15 17 16 16 -1 17 17 16 16 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3852, '15 17 16 16 23 -1 17 17 16 16 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3853, '15 17 16 16 0 -1 17 17 16 16 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3854, '15 17 16 16 18 -1 17 17 16 16 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3855, '15 17 16 16 18 0 -1 17 17 16 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3856, '15 17 16 16 18 18 -1 17 17 16 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3857, '15 17 16 16 18 0 18 -1 17 17 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3858, '15 17 16 16 21 -1 17 17 16 16 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3859, '15 17 16 16 21 0 -1 17 17 16 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3860, '15 17 16 16 25 -1 17 17 16 16 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3861, '15 17 16 16 0 21 -1 17 17 16 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3862, '15 17 16 16 0 0 -1 17 17 16 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3863, '15 17 16 16 0 18 -1 17 17 16 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3864, '15 17 16 16 0 1 -1 17 17 16 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3865, '15 17 16 16 1 -1 17 17 16 16 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3866, '17 17 -1 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3867, '17 17 23 -1 17 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3868, '17 17 0 -1 17 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3869, '17 17 18 -1 17 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3870, '17 17 18 0 -1 17 17 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3871, '17 17 18 18 -1 17 17 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3872, '17 17 18 0 18 -1 17 17 17 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3873, '17 17 21 -1 17 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3874, '17 17 21 0 -1 17 17 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3875, '17 17 25 -1 17 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3876, '17 17 0 21 -1 17 17 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3877, '17 17 0 0 -1 17 17 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3878, '17 17 0 18 -1 17 17 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3879, '17 17 0 1 -1 17 17 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3880, '17 17 1 -1 17 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3881, '17 17 16 -1 17 17 16 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3882, '17 17 16 23 -1 17 17 16 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3883, '17 17 16 0 -1 17 17 16 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3884, '17 17 16 18 -1 17 17 16 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3885, '17 17 16 18 0 -1 17 17 16 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3886, '17 17 16 18 18 -1 17 17 16 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3887, '17 17 16 18 0 18 -1 17 17 16 17 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3888, '17 17 16 21 -1 17 17 16 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3889, '17 17 16 21 0 -1 17 17 16 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3890, '17 17 16 25 -1 17 17 16 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3891, '17 17 16 0 21 -1 17 17 16 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3892, '17 17 16 0 0 -1 17 17 16 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3893, '17 17 16 0 18 -1 17 17 16 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3894, '17 17 16 0 1 -1 17 17 16 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3895, '17 17 16 1 -1 17 17 16 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3896, '17 17 16 16 -1 17 17 16 16 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3897, '17 17 16 16 23 -1 17 17 16 16 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3898, '17 17 16 16 0 -1 17 17 16 16 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3899, '17 17 16 16 18 -1 17 17 16 16 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3900, '17 17 16 16 18 0 -1 17 17 16 16 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3901, '17 17 16 16 18 18 -1 17 17 16 16 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3902, '17 17 16 16 18 0 18 -1 17 17 16 16 17 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3903, '17 17 16 16 21 -1 17 17 16 16 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3904, '17 17 16 16 21 0 -1 17 17 16 16 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3905, '17 17 16 16 25 -1 17 17 16 16 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3906, '17 17 16 16 0 21 -1 17 17 16 16 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3907, '17 17 16 16 0 0 -1 17 17 16 16 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3908, '17 17 16 16 0 18 -1 17 17 16 16 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3909, '17 17 16 16 0 1 -1 17 17 16 16 17 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3910, '17 17 16 16 1 -1 17 17 16 16 17 -1 4 16');
INSERT INTO pagc_rules (id, rule) VALUES (3911, '17 -1 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3912, '15 17 -1 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3913, '17 17 -1 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3914, '23 17 -1 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3915, '23 15 17 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3916, '23 17 17 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3917, '0 17 -1 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3918, '0 15 17 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3919, '0 17 17 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3920, '18 17 -1 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3921, '18 15 17 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3922, '18 17 17 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3923, '18 0 17 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3924, '18 0 15 17 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3925, '18 0 17 17 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3926, '18 18 17 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3927, '18 18 15 17 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3928, '18 18 17 17 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3929, '18 0 18 17 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3930, '18 0 18 15 17 -1 17 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3931, '18 0 18 17 17 -1 17 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3932, '21 17 -1 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3933, '21 15 17 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3934, '21 17 17 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3935, '21 0 17 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3936, '21 0 15 17 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3937, '21 0 17 17 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3938, '25 17 -1 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3939, '25 15 17 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3940, '25 17 17 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3941, '0 21 17 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3942, '0 21 15 17 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3943, '0 21 17 17 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3944, '0 0 17 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3945, '0 0 15 17 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3946, '0 0 17 17 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3947, '0 18 17 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3948, '0 18 15 17 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3949, '0 18 17 17 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3950, '0 1 17 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3951, '0 1 15 17 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3952, '0 1 17 17 -1 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3953, '1 17 -1 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3954, '1 15 17 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3955, '1 17 17 -1 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3956, '16 17 -1 16 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3957, '16 15 17 -1 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3958, '16 17 17 -1 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3959, '16 23 17 -1 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3960, '16 23 15 17 -1 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3961, '16 23 17 17 -1 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3962, '16 0 17 -1 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3963, '16 0 15 17 -1 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3964, '16 0 17 17 -1 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3965, '16 18 17 -1 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3966, '16 18 15 17 -1 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3967, '16 18 17 17 -1 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3968, '16 18 0 17 -1 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3969, '16 18 0 15 17 -1 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3970, '16 18 0 17 17 -1 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3971, '16 18 18 17 -1 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3972, '16 18 18 15 17 -1 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3973, '16 18 18 17 17 -1 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3974, '16 18 0 18 17 -1 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3975, '16 18 0 18 15 17 -1 16 17 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3976, '16 18 0 18 17 17 -1 16 17 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3977, '16 21 17 -1 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3978, '16 21 15 17 -1 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3979, '16 21 17 17 -1 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3980, '16 21 0 17 -1 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3981, '16 21 0 15 17 -1 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3982, '16 21 0 17 17 -1 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3983, '16 25 17 -1 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3984, '16 25 15 17 -1 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3985, '16 25 17 17 -1 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3986, '16 0 21 17 -1 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3987, '16 0 21 15 17 -1 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3988, '16 0 21 17 17 -1 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3989, '16 0 0 17 -1 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3990, '16 0 0 15 17 -1 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3991, '16 0 0 17 17 -1 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3992, '16 0 18 17 -1 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3993, '16 0 18 15 17 -1 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3994, '16 0 18 17 17 -1 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3995, '16 0 1 17 -1 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3996, '16 0 1 15 17 -1 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3997, '16 0 1 17 17 -1 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3998, '16 1 17 -1 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (3999, '16 1 15 17 -1 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4000, '16 1 17 17 -1 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4001, '16 16 17 -1 16 16 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4002, '16 16 15 17 -1 16 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4003, '16 16 17 17 -1 16 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4004, '16 16 23 17 -1 16 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4005, '16 16 23 15 17 -1 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4006, '16 16 23 17 17 -1 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4007, '16 16 0 17 -1 16 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4008, '16 16 0 15 17 -1 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4009, '16 16 0 17 17 -1 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4010, '16 16 18 17 -1 16 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4011, '16 16 18 15 17 -1 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4012, '16 16 18 17 17 -1 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4013, '16 16 18 0 17 -1 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4014, '16 16 18 0 15 17 -1 16 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4015, '16 16 18 0 17 17 -1 16 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4016, '16 16 18 18 17 -1 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4017, '16 16 18 18 15 17 -1 16 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4018, '16 16 18 18 17 17 -1 16 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4019, '16 16 18 0 18 17 -1 16 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4020, '16 16 18 0 18 15 17 -1 16 16 17 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4021, '16 16 18 0 18 17 17 -1 16 16 17 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4022, '16 16 21 17 -1 16 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4023, '16 16 21 15 17 -1 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4024, '16 16 21 17 17 -1 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4025, '16 16 21 0 17 -1 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4026, '16 16 21 0 15 17 -1 16 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4027, '16 16 21 0 17 17 -1 16 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4028, '16 16 25 17 -1 16 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4029, '16 16 25 15 17 -1 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4030, '16 16 25 17 17 -1 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4031, '16 16 0 21 17 -1 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4032, '16 16 0 21 15 17 -1 16 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4033, '16 16 0 21 17 17 -1 16 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4034, '16 16 0 0 17 -1 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4035, '16 16 0 0 15 17 -1 16 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4036, '16 16 0 0 17 17 -1 16 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4037, '16 16 0 18 17 -1 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4038, '16 16 0 18 15 17 -1 16 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4039, '16 16 0 18 17 17 -1 16 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4040, '16 16 0 1 17 -1 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4041, '16 16 0 1 15 17 -1 16 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4042, '16 16 0 1 17 17 -1 16 16 17 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4043, '16 16 1 17 -1 16 16 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4044, '16 16 1 15 17 -1 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4045, '16 16 1 17 17 -1 16 16 17 17 17 -1 4 8');
INSERT INTO pagc_rules (id, rule) VALUES (4046, '12 -1 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4047, '12 23 23 13 13 -1 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4048, '12 0 -1 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4049, '12 0 0 -1 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4050, '12 27 -1 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4051, '12 27 26 -1 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4052, '12 28 -1 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4053, '12 28 29 -1 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4054, '23 23 13 13 -1 -1 0 14');
INSERT INTO pagc_rules (id, rule) VALUES (4055, '23 23 13 13 12 -1 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4056, '0 -1 13 -1 0 14');
INSERT INTO pagc_rules (id, rule) VALUES (4057, '0 12 -1 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4058, '0 0 -1 13 13 -1 0 14');
INSERT INTO pagc_rules (id, rule) VALUES (4059, '0 0 12 -1 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4060, '27 -1 13 -1 0 14');
INSERT INTO pagc_rules (id, rule) VALUES (4061, '27 12 -1 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4062, '27 26 -1 13 13 -1 0 14');
INSERT INTO pagc_rules (id, rule) VALUES (4063, '27 26 12 -1 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4064, '28 -1 13 -1 0 14');
INSERT INTO pagc_rules (id, rule) VALUES (4065, '28 12 -1 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4066, '28 29 -1 13 13 -1 0 14');
INSERT INTO pagc_rules (id, rule) VALUES (4067, '28 29 12 -1 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4068, '11 -1 11 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4069, '11 23 23 13 13 -1 11 -1 0 7');
INSERT INTO pagc_rules (id, rule) VALUES (4070, '11 0 -1 11 13 -1 0 7');
INSERT INTO pagc_rules (id, rule) VALUES (4071, '11 0 0 -1 11 13 13 -1 0 7');
INSERT INTO pagc_rules (id, rule) VALUES (4072, '11 27 -1 11 13 -1 0 7');
INSERT INTO pagc_rules (id, rule) VALUES (4073, '11 27 26 -1 11 13 13 -1 0 7');
INSERT INTO pagc_rules (id, rule) VALUES (4074, '11 28 -1 11 13 -1 0 7');
INSERT INTO pagc_rules (id, rule) VALUES (4075, '11 28 29 -1 11 13 13 -1 0 7');
INSERT INTO pagc_rules (id, rule) VALUES (4076, '10 -1 10 -1 0 5');
INSERT INTO pagc_rules (id, rule) VALUES (4077, '10 12 -1 10 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4078, '10 12 23 23 13 13 -1 10 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4079, '10 12 0 -1 10 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4080, '10 12 0 0 -1 10 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4081, '10 12 27 -1 10 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4082, '10 12 27 26 -1 10 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4083, '10 12 28 -1 10 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4084, '10 12 28 29 -1 10 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4085, '10 23 23 13 13 -1 10 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4086, '10 23 23 13 13 12 -1 10 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4087, '10 0 -1 10 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4088, '10 0 12 -1 10 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4089, '10 0 0 -1 10 13 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4090, '10 0 0 12 -1 10 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4091, '10 27 -1 10 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4092, '10 27 12 -1 10 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4093, '10 27 26 -1 10 13 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4094, '10 27 26 12 -1 10 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4095, '10 28 -1 10 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4096, '10 28 12 -1 10 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4097, '10 28 29 -1 10 13 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4098, '10 28 29 12 -1 10 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4099, '10 11 -1 10 11 -1 0 13');
INSERT INTO pagc_rules (id, rule) VALUES (4100, '10 11 12 -1 10 11 12 -1 0 15');
INSERT INTO pagc_rules (id, rule) VALUES (4101, '10 11 12 23 23 13 13 -1 10 11 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4102, '10 11 12 0 -1 10 11 12 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4103, '10 11 12 0 0 -1 10 11 12 13 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4104, '10 11 12 27 -1 10 11 12 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4105, '10 11 12 27 26 -1 10 11 12 13 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4106, '10 11 12 28 -1 10 11 12 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4107, '10 11 12 28 29 -1 10 11 12 13 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4108, '10 11 23 23 13 13 -1 10 11 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4109, '10 11 23 23 13 13 12 -1 10 11 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4110, '10 11 0 -1 10 11 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4111, '10 11 0 12 -1 10 11 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4112, '10 11 0 0 -1 10 11 13 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4113, '10 11 0 0 12 -1 10 11 13 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4114, '10 11 27 -1 10 11 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4115, '10 11 27 12 -1 10 11 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4116, '10 11 27 26 -1 10 11 13 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4117, '10 11 27 26 12 -1 10 11 13 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4118, '10 11 28 -1 10 11 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4119, '10 11 28 12 -1 10 11 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4120, '10 11 28 29 -1 10 11 13 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4121, '10 11 28 29 12 -1 10 11 13 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4122, '1 -1 10 -1 0 5');
INSERT INTO pagc_rules (id, rule) VALUES (4123, '1 12 -1 10 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4124, '1 12 23 23 13 13 -1 10 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4125, '1 12 0 -1 10 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4126, '1 12 0 0 -1 10 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4127, '1 12 27 -1 10 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4128, '1 12 27 26 -1 10 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4129, '1 12 28 -1 10 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4130, '1 12 28 29 -1 10 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4131, '1 23 23 13 13 -1 10 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4132, '1 23 23 13 13 12 -1 10 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4133, '1 0 -1 10 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4134, '1 0 12 -1 10 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4135, '1 0 0 -1 10 13 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4136, '1 0 0 12 -1 10 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4137, '1 27 -1 10 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4138, '1 27 12 -1 10 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4139, '1 27 26 -1 10 13 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4140, '1 27 26 12 -1 10 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4141, '1 28 -1 10 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4142, '1 28 12 -1 10 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4143, '1 28 29 -1 10 13 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4144, '1 28 29 12 -1 10 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4145, '1 11 -1 10 11 -1 0 13');
INSERT INTO pagc_rules (id, rule) VALUES (4146, '1 11 12 -1 10 11 12 -1 0 15');
INSERT INTO pagc_rules (id, rule) VALUES (4147, '1 11 12 23 23 13 13 -1 10 11 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4148, '1 11 12 0 -1 10 11 12 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4149, '1 11 12 0 0 -1 10 11 12 13 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4150, '1 11 12 27 -1 10 11 12 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4151, '1 11 12 27 26 -1 10 11 12 13 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4152, '1 11 12 28 -1 10 11 12 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4153, '1 11 12 28 29 -1 10 11 12 13 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4154, '1 11 23 23 13 13 -1 10 11 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4155, '1 11 23 23 13 13 12 -1 10 11 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4156, '1 11 0 -1 10 11 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4157, '1 11 0 12 -1 10 11 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4158, '1 11 0 0 -1 10 11 13 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4159, '1 11 0 0 12 -1 10 11 13 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4160, '1 11 27 -1 10 11 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4161, '1 11 27 12 -1 10 11 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4162, '1 11 27 26 -1 10 11 13 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4163, '1 11 27 26 12 -1 10 11 13 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4164, '1 11 28 -1 10 11 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4165, '1 11 28 12 -1 10 11 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4166, '1 11 28 29 -1 10 11 13 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4167, '1 11 28 29 12 -1 10 11 13 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4168, '22 1 -1 10 10 -1 0 5');
INSERT INTO pagc_rules (id, rule) VALUES (4169, '22 1 12 -1 10 10 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4170, '22 1 12 23 23 13 13 -1 10 10 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4171, '22 1 12 0 -1 10 10 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4172, '22 1 12 0 0 -1 10 10 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4173, '22 1 12 27 -1 10 10 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4174, '22 1 12 27 26 -1 10 10 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4175, '22 1 12 28 -1 10 10 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4176, '22 1 12 28 29 -1 10 10 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4177, '22 1 23 23 13 13 -1 10 10 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4178, '22 1 23 23 13 13 12 -1 10 10 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4179, '22 1 0 -1 10 10 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4180, '22 1 0 12 -1 10 10 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4181, '22 1 0 0 -1 10 10 13 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4182, '22 1 0 0 12 -1 10 10 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4183, '22 1 27 -1 10 10 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4184, '22 1 27 12 -1 10 10 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4185, '22 1 27 26 -1 10 10 13 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4186, '22 1 27 26 12 -1 10 10 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4187, '22 1 28 -1 10 10 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4188, '22 1 28 12 -1 10 10 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4189, '22 1 28 29 -1 10 10 13 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4190, '22 1 28 29 12 -1 10 10 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4191, '22 1 11 -1 10 10 11 -1 0 13');
INSERT INTO pagc_rules (id, rule) VALUES (4192, '22 1 11 12 -1 10 10 11 12 -1 0 15');
INSERT INTO pagc_rules (id, rule) VALUES (4193, '22 1 11 12 23 23 13 13 -1 10 10 11 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4194, '22 1 11 12 0 -1 10 10 11 12 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4195, '22 1 11 12 0 0 -1 10 10 11 12 13 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4196, '22 1 11 12 27 -1 10 10 11 12 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4197, '22 1 11 12 27 26 -1 10 10 11 12 13 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4198, '22 1 11 12 28 -1 10 10 11 12 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4199, '22 1 11 12 28 29 -1 10 10 11 12 13 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4200, '22 1 11 23 23 13 13 -1 10 10 11 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4201, '22 1 11 23 23 13 13 12 -1 10 10 11 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4202, '22 1 11 0 -1 10 10 11 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4203, '22 1 11 0 12 -1 10 10 11 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4204, '22 1 11 0 0 -1 10 10 11 13 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4205, '22 1 11 0 0 12 -1 10 10 11 13 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4206, '22 1 11 27 -1 10 10 11 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4207, '22 1 11 27 12 -1 10 10 11 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4208, '22 1 11 27 26 -1 10 10 11 13 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4209, '22 1 11 27 26 12 -1 10 10 11 13 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4210, '22 1 11 28 -1 10 10 11 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4211, '22 1 11 28 12 -1 10 10 11 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4212, '22 1 11 28 29 -1 10 10 11 13 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4213, '22 1 11 28 29 12 -1 10 10 11 13 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4214, '1 22 -1 10 10 -1 0 5');
INSERT INTO pagc_rules (id, rule) VALUES (4215, '1 22 12 -1 10 10 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4216, '1 22 12 23 23 13 13 -1 10 10 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4217, '1 22 12 0 -1 10 10 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4218, '1 22 12 0 0 -1 10 10 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4219, '1 22 12 27 -1 10 10 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4220, '1 22 12 27 26 -1 10 10 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4221, '1 22 12 28 -1 10 10 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4222, '1 22 12 28 29 -1 10 10 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4223, '1 22 23 23 13 13 -1 10 10 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4224, '1 22 23 23 13 13 12 -1 10 10 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4225, '1 22 0 -1 10 10 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4226, '1 22 0 12 -1 10 10 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4227, '1 22 0 0 -1 10 10 13 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4228, '1 22 0 0 12 -1 10 10 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4229, '1 22 27 -1 10 10 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4230, '1 22 27 12 -1 10 10 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4231, '1 22 27 26 -1 10 10 13 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4232, '1 22 27 26 12 -1 10 10 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4233, '1 22 28 -1 10 10 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4234, '1 22 28 12 -1 10 10 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4235, '1 22 28 29 -1 10 10 13 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4236, '1 22 28 29 12 -1 10 10 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4237, '1 22 11 -1 10 10 11 -1 0 13');
INSERT INTO pagc_rules (id, rule) VALUES (4238, '1 22 11 12 -1 10 10 11 12 -1 0 15');
INSERT INTO pagc_rules (id, rule) VALUES (4239, '1 22 11 12 23 23 13 13 -1 10 10 11 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4240, '1 22 11 12 0 -1 10 10 11 12 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4241, '1 22 11 12 0 0 -1 10 10 11 12 13 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4242, '1 22 11 12 27 -1 10 10 11 12 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4243, '1 22 11 12 27 26 -1 10 10 11 12 13 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4244, '1 22 11 12 28 -1 10 10 11 12 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4245, '1 22 11 12 28 29 -1 10 10 11 12 13 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4246, '1 22 11 23 23 13 13 -1 10 10 11 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4247, '1 22 11 23 23 13 13 12 -1 10 10 11 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4248, '1 22 11 0 -1 10 10 11 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4249, '1 22 11 0 12 -1 10 10 11 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4250, '1 22 11 0 0 -1 10 10 11 13 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4251, '1 22 11 0 0 12 -1 10 10 11 13 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4252, '1 22 11 27 -1 10 10 11 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4253, '1 22 11 27 12 -1 10 10 11 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4254, '1 22 11 27 26 -1 10 10 11 13 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4255, '1 22 11 27 26 12 -1 10 10 11 13 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4256, '1 22 11 28 -1 10 10 11 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4257, '1 22 11 28 12 -1 10 10 11 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4258, '1 22 11 28 29 -1 10 10 11 13 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4259, '1 22 11 28 29 12 -1 10 10 11 13 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4260, '2 1 -1 10 10 -1 0 5');
INSERT INTO pagc_rules (id, rule) VALUES (4261, '2 1 12 -1 10 10 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4262, '2 1 12 23 23 13 13 -1 10 10 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4263, '2 1 12 0 -1 10 10 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4264, '2 1 12 0 0 -1 10 10 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4265, '2 1 12 27 -1 10 10 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4266, '2 1 12 27 26 -1 10 10 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4267, '2 1 12 28 -1 10 10 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4268, '2 1 12 28 29 -1 10 10 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4269, '2 1 23 23 13 13 -1 10 10 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4270, '2 1 23 23 13 13 12 -1 10 10 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4271, '2 1 0 -1 10 10 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4272, '2 1 0 12 -1 10 10 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4273, '2 1 0 0 -1 10 10 13 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4274, '2 1 0 0 12 -1 10 10 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4275, '2 1 27 -1 10 10 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4276, '2 1 27 12 -1 10 10 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4277, '2 1 27 26 -1 10 10 13 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4278, '2 1 27 26 12 -1 10 10 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4279, '2 1 28 -1 10 10 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4280, '2 1 28 12 -1 10 10 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4281, '2 1 28 29 -1 10 10 13 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4282, '2 1 28 29 12 -1 10 10 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4283, '2 1 11 -1 10 10 11 -1 0 13');
INSERT INTO pagc_rules (id, rule) VALUES (4284, '2 1 11 12 -1 10 10 11 12 -1 0 15');
INSERT INTO pagc_rules (id, rule) VALUES (4285, '2 1 11 12 23 23 13 13 -1 10 10 11 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4286, '2 1 11 12 0 -1 10 10 11 12 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4287, '2 1 11 12 0 0 -1 10 10 11 12 13 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4288, '2 1 11 12 27 -1 10 10 11 12 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4289, '2 1 11 12 27 26 -1 10 10 11 12 13 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4290, '2 1 11 12 28 -1 10 10 11 12 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4291, '2 1 11 12 28 29 -1 10 10 11 12 13 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4292, '2 1 11 23 23 13 13 -1 10 10 11 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4293, '2 1 11 23 23 13 13 12 -1 10 10 11 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4294, '2 1 11 0 -1 10 10 11 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4295, '2 1 11 0 12 -1 10 10 11 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4296, '2 1 11 0 0 -1 10 10 11 13 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4297, '2 1 11 0 0 12 -1 10 10 11 13 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4298, '2 1 11 27 -1 10 10 11 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4299, '2 1 11 27 12 -1 10 10 11 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4300, '2 1 11 27 26 -1 10 10 11 13 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4301, '2 1 11 27 26 12 -1 10 10 11 13 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4302, '2 1 11 28 -1 10 10 11 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4303, '2 1 11 28 12 -1 10 10 11 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4304, '2 1 11 28 29 -1 10 10 11 13 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4305, '2 1 11 28 29 12 -1 10 10 11 13 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4306, '1 2 -1 10 10 -1 0 5');
INSERT INTO pagc_rules (id, rule) VALUES (4307, '1 2 12 -1 10 10 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4308, '1 2 12 23 23 13 13 -1 10 10 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4309, '1 2 12 0 -1 10 10 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4310, '1 2 12 0 0 -1 10 10 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4311, '1 2 12 27 -1 10 10 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4312, '1 2 12 27 26 -1 10 10 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4313, '1 2 12 28 -1 10 10 12 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4314, '1 2 12 28 29 -1 10 10 12 13 13 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4315, '1 2 23 23 13 13 -1 10 10 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4316, '1 2 23 23 13 13 12 -1 10 10 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4317, '1 2 0 -1 10 10 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4318, '1 2 0 12 -1 10 10 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4319, '1 2 0 0 -1 10 10 13 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4320, '1 2 0 0 12 -1 10 10 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4321, '1 2 27 -1 10 10 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4322, '1 2 27 12 -1 10 10 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4323, '1 2 27 26 -1 10 10 13 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4324, '1 2 27 26 12 -1 10 10 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4325, '1 2 28 -1 10 10 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4326, '1 2 28 12 -1 10 10 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4327, '1 2 28 29 -1 10 10 13 13 -1 0 9');
INSERT INTO pagc_rules (id, rule) VALUES (4328, '1 2 28 29 12 -1 10 10 13 13 12 -1 0 3');
INSERT INTO pagc_rules (id, rule) VALUES (4329, '1 2 11 -1 10 10 11 -1 0 13');
INSERT INTO pagc_rules (id, rule) VALUES (4330, '1 2 11 12 -1 10 10 11 12 -1 0 15');
INSERT INTO pagc_rules (id, rule) VALUES (4331, '1 2 11 12 23 23 13 13 -1 10 10 11 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4332, '1 2 11 12 0 -1 10 10 11 12 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4333, '1 2 11 12 0 0 -1 10 10 11 12 13 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4334, '1 2 11 12 27 -1 10 10 11 12 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4335, '1 2 11 12 27 26 -1 10 10 11 12 13 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4336, '1 2 11 12 28 -1 10 10 11 12 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4337, '1 2 11 12 28 29 -1 10 10 11 12 13 13 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4338, '1 2 11 23 23 13 13 -1 10 10 11 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4339, '1 2 11 23 23 13 13 12 -1 10 10 11 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4340, '1 2 11 0 -1 10 10 11 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4341, '1 2 11 0 12 -1 10 10 11 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4342, '1 2 11 0 0 -1 10 10 11 13 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4343, '1 2 11 0 0 12 -1 10 10 11 13 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4344, '1 2 11 27 -1 10 10 11 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4345, '1 2 11 27 12 -1 10 10 11 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4346, '1 2 11 27 26 -1 10 10 11 13 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4347, '1 2 11 27 26 12 -1 10 10 11 13 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4348, '1 2 11 28 -1 10 10 11 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4349, '1 2 11 28 12 -1 10 10 11 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) VALUES (4350, '1 2 11 28 29 -1 10 10 11 13 13 -1 0 16');
INSERT INTO pagc_rules (id, rule) VALUES (4351, '1 2 11 28 29 12 -1 10 10 11 13 13 12 -1 0 17');
INSERT INTO pagc_rules (id, rule) values (4352, '16 0 22 -1 16 17 17 -1 4 7');
INSERT INTO pagc_rules (id, rule) VALUES (4353, '0 1 6 -1 1 5 5 -1 1 9');
INSERT INTO pagc_rules (id, rule) VALUES (4355, '-1');

-- for some reason all rules are coming in as custom.  just force by id
UPDATE tiger.pagc_rules SET is_custom = false where id < 10000;
-- after insert we need to set back to true so all
-- user inputs are treated as custom
ALTER TABLE tiger.pagc_rules ALTER COLUMN is_custom SET DEFAULT true;
SELECT pg_catalog.setval('pagc_rules_id_seq', 10000, true);-- pagc_normalize_address(addressString)
-- This takes an address string and parses it into address (internal/street)
-- street name, type, direction prefix and suffix, location, state and
-- zip code, depending on what can be found in the string.
-- This is a drop in replacement for packaged normalize_address
-- that uses the pagc address standardizer C library instead
-- USAGE: SELECT * FROM tiger.pagc_normalize_address('One Devonshire Place, PH 301, Boston, MA 02109');
SELECT tiger.SetSearchPathForInstall('tiger');
CREATE OR REPLACE FUNCTION pagc_normalize_address(in_rawinput character varying)
  RETURNS norm_addy AS
$$
DECLARE
  result norm_addy;
  var_rec RECORD;
  var_parse_rec RECORD;
  rawInput VARCHAR;

BEGIN
  result.parsed := FALSE;

  rawInput := trim(in_rawinput);
  var_parse_rec := parse_address(rawInput);
  result.location := var_parse_rec.city;
  result.stateAbbrev := trim(var_parse_rec.state);
  result.zip := var_parse_rec.zip;
  result.zip4 := NULLIF(var_parse_rec.zipplus,'');

 var_rec := standardize_address('pagc_lex'
       , 'pagc_gaz'
       , 'pagc_rules'
, COALESCE(var_parse_rec.address1,''),
   COALESCE(var_parse_rec.city,'') || COALESCE(', ' || var_parse_rec.state, '') || COALESCE(' ' || var_parse_rec.zip,'')  ) ;

 -- For address number only put numbers and stop if reach a non-number e.g. 123-456 will return 123
  result.address := to_number(substring(var_rec.house_num, '[0-9]+'), '99999999');
  result.address_alphanumeric := var_rec.house_num;
   --get rid of extraneous spaces before we return
  result.zip := COALESCE(var_rec.postcode,result.zip);
  result.streetName := trim(var_rec.name);
  result.location := trim(var_rec.city);
  result.stateAbbrev := trim(var_rec.state);
  --this should be broken out separately like pagc, but normalizer doesn't have a slot for it
  result.streettypeAbbrev := trim(COALESCE(var_rec.suftype, var_rec.pretype));
  result.preDirAbbrev := trim(var_rec.predir);
  result.postDirAbbrev := trim(var_rec.sufdir);
  result.internal := trim(regexp_replace(replace(var_rec.unit, '#',''), '([0-9]+)\s+([A-Za-z]){0,1}', E'\\1\\2'));
  result.parsed := TRUE;
  RETURN result;
END
$$
  LANGUAGE plpgsql IMMUTABLE STRICT
  COST 100; /***
 *
 * Copyright (C) 2011 Regina Obe and Leo Hsu (Paragon Corporation)
 **/
-- Note we are wrapping this in a function so we can make it immutable and thus usable in an index
-- It also allows us to shorten and possibly better cache the repetitive pattern in the code
-- greatest(to_number(b.fromhn,''99999999''),to_number(b.tohn,''99999999''))
-- and least(to_number(b.fromhn,''99999999''),to_number(b.tohn,''99999999''))
CREATE OR REPLACE FUNCTION least_hn(fromhn varchar, tohn varchar)
  RETURNS integer AS
$$ SELECT least(to_number( CASE WHEN trim($1) ~ '^[0-9]+$' THEN $1 ELSE '0' END,'9999999'),to_number(CASE WHEN trim($2) ~ '^[0-9]+$' THEN $2 ELSE '0' END,'9999999') )::integer;  $$
  LANGUAGE sql IMMUTABLE
  COST 200;

-- Note we are wrapping this in a function so we can make it immutable (for some reason least and greatest aren't considered immutable)
-- and thu usable in an index or cacheable for multiple calls
CREATE OR REPLACE FUNCTION greatest_hn(fromhn varchar, tohn varchar)
  RETURNS integer AS
$$ SELECT greatest(to_number( CASE WHEN trim($1) ~ '^[0-9]+$' THEN $1 ELSE '0' END,'99999999'),to_number(CASE WHEN trim($2) ~ '^[0-9]+$' THEN $2 ELSE '0' END,'99999999') )::integer;  $$
  LANGUAGE sql IMMUTABLE
  COST 200 PARALLEL SAFE;

-- Returns an absolute difference between two zips
-- This is generally more efficient than doing levenshtein
-- Since when people get the wrong zip, its usually off by one or 2 numeric distance
-- We only consider the first 5 digits
CREATE OR REPLACE FUNCTION diff_zip(zip1 varchar, zip2 varchar)
  RETURNS integer AS
$$ SELECT abs(to_number( CASE WHEN trim(substring($1,1,5)) ~ '^[0-9]+$' THEN $1 ELSE '0' END,'99999')::integer - to_number( CASE WHEN trim(substring($2,1,5)) ~ '^[0-9]+$' THEN $2 ELSE '0' END,'99999')::integer )::integer;  $$
  LANGUAGE sql IMMUTABLE STRICT
  COST 200 PARALLEL SAFE;

-- function return  true or false if 2 numeric streets are equal such as 15th St, 23rd st
-- it compares just the numeric part of the street for equality
-- PURPOSE: handle bad formats such as 23th St so 23th St = 23rd St
-- as described in: http://trac.osgeo.org/postgis/ticket/1068
-- This will always return false if one of the streets is not a numeric street
-- By numeric it must start with numbers (allow fractions such as 1/2 and spaces such as 12 1/2th) and be less than 10 characters
CREATE OR REPLACE FUNCTION numeric_streets_equal(input_street varchar, output_street varchar)
    RETURNS boolean AS
$$
    SELECT COALESCE(length($1) < 10 AND length($2) < 10
            AND $1 ~ E'^[0-9\/\s]+' AND $2 ~ E'^[0-9\/\s]+'
            AND  trim(substring($1, E'^[0-9\/\s]+')) = trim(substring($2, E'^[0-9\/\s]+')), false);
$$
LANGUAGE sql IMMUTABLE
COST 5 PARALLEL SAFE;

-- Generate script to drop all non-primary unique indexes on tiger and tiger_data tables
CREATE OR REPLACE FUNCTION drop_indexes_generate_script(tiger_data_schema text DEFAULT 'tiger_data')
RETURNS text AS
$$
SELECT array_to_string(ARRAY(SELECT 'DROP INDEX ' || schemaname || '.' || indexname || ';'
FROM pg_catalog.pg_indexes  where schemaname IN('tiger',$1)  AND indexname NOT LIKE 'uidx%' AND indexname NOT LIKE 'pk_%' AND indexname NOT LIKE '%key'), E'\n');
$$
LANGUAGE sql STABLE;
-- Generate script to create missing indexes in tiger tables.
-- This will generate sql you can run to index commonly used join columns in geocoder for tiger and tiger_data schemas --
CREATE OR REPLACE FUNCTION missing_indexes_generate_script()
RETURNS text AS
$$
SELECT array_to_string(ARRAY(
-- create unique index on faces for tfid seems to perform better --
SELECT 'CREATE UNIQUE INDEX uidx_' || c.table_schema || '_' || c.table_name || '_' || c.column_name || ' ON ' || c.table_schema || '.' || c.table_name || ' USING btree(' || c.column_name || ');' As index
FROM (SELECT table_name, table_schema  FROM
	information_schema.tables WHERE table_type = 'BASE TABLE') As t  INNER JOIN
	(SELECT * FROM information_schema.columns WHERE column_name IN('tfid') ) AS c
		ON (t.table_name = c.table_name AND t.table_schema = c.table_schema)
		LEFT JOIN pg_catalog.pg_indexes i ON
			(i.tablename = c.table_name AND i.schemaname = c.table_schema
				AND  indexname LIKE 'uidx%' || c.column_name || '%' )
WHERE i.tablename IS NULL AND c.table_schema IN('tiger','tiger_data') AND c.table_name LIKE '%faces'
UNION ALL
-- basic btree regular indexes
SELECT 'CREATE INDEX idx_' || c.table_schema || '_' || c.table_name || '_' || c.column_name || ' ON ' || c.table_schema || '.' || c.table_name || ' USING btree(' || c.column_name || ');' As index
FROM (SELECT table_name, table_schema  FROM
	information_schema.tables WHERE table_type = 'BASE TABLE') As t  INNER JOIN
	(SELECT * FROM information_schema.columns WHERE column_name IN('countyfp', 'tlid', 'tfidl', 'tfidr', 'tfid', 'zip', 'placefp', 'cousubfp') ) AS c
		ON (t.table_name = c.table_name AND t.table_schema = c.table_schema)
		LEFT JOIN pg_catalog.pg_indexes i ON
			(i.tablename = c.table_name AND i.schemaname = c.table_schema
				AND  indexdef LIKE '%' || c.column_name || '%' )
WHERE i.tablename IS NULL AND c.table_schema IN('tiger','tiger_data')  AND (NOT c.table_name LIKE '%faces')
-- Gist spatial indexes --
UNION ALL
SELECT 'CREATE INDEX idx_' || c.table_schema || '_' || c.table_name || '_' || c.column_name || '_gist ON ' || c.table_schema || '.' || c.table_name || ' USING gist(' || c.column_name || ');' As index
FROM (SELECT table_name, table_schema FROM
	information_schema.tables WHERE table_type = 'BASE TABLE') As t  INNER JOIN
	(SELECT * FROM information_schema.columns WHERE column_name IN('the_geom', 'geom') ) AS c
		ON (t.table_name = c.table_name AND t.table_schema = c.table_schema)
		LEFT JOIN pg_catalog.pg_indexes i ON
			(i.tablename = c.table_name AND i.schemaname = c.table_schema
				AND  indexdef LIKE '%' || c.column_name || '%')
WHERE i.tablename IS NULL AND c.table_schema IN('tiger','tiger_data')
-- Soundex indexes --
UNION ALL
SELECT 'CREATE INDEX idx_' || c.table_schema || '_' || c.table_name || '_snd_' || c.column_name || ' ON ' || c.table_schema || '.' || c.table_name || ' USING btree(soundex(' || c.column_name || '));' As index
FROM (SELECT table_name, table_schema FROM
	information_schema.tables WHERE table_type = 'BASE TABLE') As t  INNER JOIN
	(SELECT * FROM information_schema.columns WHERE column_name IN('name', 'place', 'city') ) AS c
		ON (t.table_name = c.table_name AND t.table_schema = c.table_schema)
		LEFT JOIN pg_catalog.pg_indexes i ON
			(i.tablename = c.table_name AND i.schemaname = c.table_schema
				AND  indexdef LIKE '%soundex(%' || c.column_name || '%' AND indexdef LIKE '%_snd_' || c.column_name || '%' )
WHERE i.tablename IS NULL AND c.table_schema IN('tiger','tiger_data')
    AND (c.table_name LIKE '%county%' OR c.table_name LIKE '%featnames'
    OR c.table_name  LIKE '%place' or c.table_name LIKE '%zip%'  or c.table_name LIKE '%cousub')
-- Lower indexes --
UNION ALL
SELECT 'CREATE INDEX idx_' || c.table_schema || '_' || c.table_name || '_lower_' || c.column_name || ' ON ' || c.table_schema || '.' || c.table_name || ' USING btree(lower(' || c.column_name || '));' As index
FROM (SELECT table_name, table_schema FROM
	information_schema.tables WHERE table_type = 'BASE TABLE') As t  INNER JOIN
	(SELECT * FROM information_schema.columns WHERE column_name IN('name', 'place', 'city') ) AS c
		ON (t.table_name = c.table_name AND t.table_schema = c.table_schema)
		LEFT JOIN pg_catalog.pg_indexes i ON
			(i.tablename = c.table_name AND i.schemaname = c.table_schema
				AND  indexdef LIKE '%btree%(%lower(%' || c.column_name || '%')
WHERE i.tablename IS NULL AND c.table_schema IN('tiger','tiger_data')
    AND (c.table_name LIKE '%county%' OR c.table_name LIKE '%featnames' OR c.table_name  LIKE '%place' or c.table_name LIKE '%zip%' or c.table_name LIKE '%cousub')
-- Least address index btree least_hn(fromhn, tohn)
UNION ALL
SELECT 'CREATE INDEX idx_' || c.table_schema || '_' || c.table_name || '_least_address' || ' ON ' || c.table_schema || '.' || c.table_name || ' USING btree(least_hn(fromhn, tohn));' As index
FROM (SELECT table_name, table_schema FROM
	information_schema.tables WHERE table_type = 'BASE TABLE' AND table_name LIKE '%addr' AND table_schema IN('tiger','tiger_data')) As t  INNER JOIN
	(SELECT * FROM information_schema.columns WHERE column_name IN('fromhn') ) AS c
		ON (t.table_name = c.table_name AND t.table_schema = c.table_schema)
		LEFT JOIN pg_catalog.pg_indexes i ON
			(i.tablename = c.table_name AND i.schemaname = c.table_schema
				AND  indexdef LIKE '%least_hn(%' || c.column_name || '%')
WHERE i.tablename IS NULL
-- var_ops lower --
UNION ALL
SELECT 'CREATE INDEX idx_' || c.table_schema || '_' || c.table_name || '_l' || c.column_name || '_var_ops' || ' ON ' || c.table_schema || '.' || c.table_name || ' USING btree(lower(' || c.column_name || ') varchar_pattern_ops);' As index
FROM (SELECT table_name, table_schema FROM
	information_schema.tables WHERE table_type = 'BASE TABLE' AND (table_name LIKE '%featnames' or table_name LIKE '%place' or table_name LIKE '%zip_lookup_base' or table_name LIKE '%zip_state_loc') AND table_schema IN('tiger','tiger_data')) As t  INNER JOIN
	(SELECT * FROM information_schema.columns WHERE column_name IN('name', 'city', 'place', 'fullname') ) AS c
		ON (t.table_name = c.table_name AND t.table_schema = c.table_schema)
		LEFT JOIN pg_catalog.pg_indexes i ON
			(i.tablename = c.table_name AND i.schemaname = c.table_schema
				AND  indexdef LIKE '%btree%(%lower%' || c.column_name || ')%varchar_pattern_ops%')
WHERE i.tablename IS NULL
-- var_ops mtfcc --
/** UNION ALL
SELECT 'CREATE INDEX idx_' || c.table_schema || '_' || c.table_name || '_' || c.column_name || '_var_ops' || ' ON ' || c.table_schema || '.' || c.table_name || ' USING btree(' || c.column_name || ' varchar_pattern_ops);' As index
FROM (SELECT table_name, table_schema FROM
	information_schema.tables WHERE table_type = 'BASE TABLE' AND (table_name LIKE '%featnames' or table_name LIKE '%edges') AND table_schema IN('tiger','tiger_data')) As t  INNER JOIN
	(SELECT * FROM information_schema.columns WHERE column_name IN('mtfcc') ) AS c
		ON (t.table_name = c.table_name AND t.table_schema = c.table_schema)
		LEFT JOIN pg_catalog.pg_indexes i ON
			(i.tablename = c.table_name AND i.schemaname = c.table_schema
				AND  indexdef LIKE '%btree%(' || c.column_name || '%varchar_pattern_ops%')
WHERE i.tablename IS NULL **/
-- zipl zipr on edges --
UNION ALL
SELECT 'CREATE INDEX idx_' || c.table_schema || '_' || c.table_name || '_' || c.column_name || ' ON ' || c.table_schema || '.' || c.table_name || ' USING btree(' || c.column_name || ' );' As index
FROM (SELECT table_name, table_schema FROM
	information_schema.tables WHERE table_type = 'BASE TABLE' AND table_name LIKE '%edges' AND table_schema IN('tiger','tiger_data')) As t  INNER JOIN
	(SELECT * FROM information_schema.columns WHERE column_name IN('zipl', 'zipr') ) AS c
		ON (t.table_name = c.table_name AND t.table_schema = c.table_schema)
		LEFT JOIN pg_catalog.pg_indexes i ON
			(i.tablename = c.table_name AND i.schemaname = c.table_schema
				AND  indexdef LIKE '%btree%(' || c.column_name || '%)%')
WHERE i.tablename IS NULL

-- unique index on tlid state county --
/*UNION ALL
SELECT 'CREATE UNIQUE INDEX uidx_' || t.table_schema || '_' || t.table_name || '_tlid_statefp_countyfp ON ' || t.table_schema || '.' || t.table_name || ' USING btree(tlid,statefp,countyfp);' As index
FROM (SELECT table_name, table_schema FROM
	information_schema.tables WHERE table_type = 'BASE TABLE' AND table_name LIKE '%edges' AND table_schema IN('tiger','tiger_data')) As t
		LEFT JOIN pg_catalog.pg_indexes i ON
			(i.tablename = t.table_name AND i.schemaname = t.table_schema
				AND  indexdef LIKE '%btree%(%tlid,%statefp%countyfp%)%')
WHERE i.tablename IS NULL*/
--full text indexes on name field--
/**UNION ALL
SELECT 'CREATE INDEX idx_' || c.table_schema || '_' || c.table_name || '_fullname_ft_gist' || ' ON ' || c.table_schema || '.' || c.table_name || ' USING gist(to_tsvector(''english'',fullname))' As index
FROM (SELECT table_name, table_schema FROM
	information_schema.tables WHERE table_type = 'BASE TABLE' AND table_name LIKE '%featnames' AND table_schema IN('tiger','tiger_data')) As t  INNER JOIN
	(SELECT * FROM information_schema.columns WHERE column_name IN('fullname') ) AS c
		ON (t.table_name = c.table_name AND t.table_schema = c.table_schema)
		LEFT JOIN pg_catalog.pg_indexes i ON
			(i.tablename = c.table_name AND i.schemaname = c.table_schema
				AND  indexdef LIKE '%to_tsvector(%' || c.column_name || '%')
WHERE i.tablename IS NULL **/

-- trigram index --
/**UNION ALL
SELECT 'CREATE INDEX idx_' || c.table_schema || '_' || c.table_name || '_' || c.column_name || '_trgm_gist' || ' ON ' || c.table_schema || '.' || c.table_name || ' USING gist(' || c.column_name || ' gist_trgm_ops);' As index
FROM (SELECT table_name, table_schema FROM
	information_schema.tables WHERE table_type = 'BASE TABLE' AND table_name LIKE '%featnames' AND table_schema IN('tiger','tiger_data')) As t  INNER JOIN
	(SELECT * FROM information_schema.columns WHERE column_name IN('fullname', 'name') ) AS c
		ON (t.table_name = c.table_name AND t.table_schema = c.table_schema)
		LEFT JOIN pg_catalog.pg_indexes i ON
			(i.tablename = c.table_name AND i.schemaname = c.table_schema
				AND  indexdef LIKE '%gist%(' || c.column_name || '%gist_trgm_ops%')
WHERE i.tablename IS NULL **/
ORDER BY 1), E'\r');
$$
LANGUAGE sql VOLATILE;

CREATE OR REPLACE FUNCTION install_missing_indexes() RETURNS boolean
AS
$$
DECLARE var_sql text = missing_indexes_generate_script();
BEGIN
	EXECUTE(var_sql);
	RETURN true;
END
$$
language plpgsql;

CREATE OR REPLACE FUNCTION drop_dupe_featnames_generate_script() RETURNS text
AS
$$

SELECT array_to_string(ARRAY(SELECT 'CREATE TEMPORARY TABLE dup AS
SELECT min(f.gid) As min_gid, f.tlid, lower(f.fullname) As fname
	FROM ONLY ' || t.table_schema || '.' || t.table_name || ' As f
	GROUP BY f.tlid, lower(f.fullname)
	HAVING count(*) > 1;

DELETE FROM ' || t.table_schema || '.' || t.table_name || ' AS feat
WHERE EXISTS (SELECT tlid FROM dup WHERE feat.tlid = dup.tlid AND lower(feat.fullname) = dup.fname
		AND feat.gid > dup.min_gid);
DROP TABLE dup;
CREATE INDEX idx_' || t.table_schema || '_' || t.table_name || '_tlid ' || ' ON ' || t.table_schema || '.' || t.table_name || ' USING btree(tlid);
' As drop_sql_create_index
FROM (SELECT table_name, table_schema FROM
	information_schema.tables WHERE table_type = 'BASE TABLE' AND (table_name LIKE '%featnames' ) AND table_schema IN('tiger','tiger_data')) As t
		LEFT JOIN pg_catalog.pg_indexes i ON
			(i.tablename = t.table_name AND i.schemaname = t.table_schema
				AND  indexdef LIKE '%btree%(%tlid%')
WHERE i.tablename IS NULL) ,E'\r');

$$
LANGUAGE sql VOLATILE;

--DROP FUNCTION IF EXISTS zip_range(text,integer,integer);
-- Helper function that useful for catch slight mistakes in zip position given a 5 digit zip code
-- will return a range of zip codes that are between zip - num_before and zip - num_after
-- e.g. usage -> zip_range('02109', -1,+1) -> {'02108', '02109', '02110'}
CREATE OR REPLACE FUNCTION zip_range(zip text, range_start integer, range_end integer) RETURNS varchar[] AS
$$
   SELECT ARRAY(
        SELECT lpad((to_number( CASE WHEN trim(substring($1,1,5)) ~ '^[0-9]+$' THEN $1 ELSE '0' END,'99999')::integer + i)::text, 5, '0')::varchar
        FROM generate_series($2, $3) As i );
$$
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE;
-- rate_attributes(dirpA, dirpB, streetNameA, streetNameB, streetTypeA,
-- streetTypeB, dirsA, dirsB, locationA, locationB)
-- Rates the street based on the given attributes.  The locations must be
-- non-null.  The other eight values are handled by the other rate_attributes
-- function, so it's requirements must also be met.
-- changed: 2010-10-18 Regina Obe - all references to verbose to var_verbose since causes compile errors in 9.0
-- changed: 2011-06-25 revise to use real named args and fix direction rating typo
CREATE OR REPLACE FUNCTION rate_attributes(dirpA VARCHAR, dirpB VARCHAR, streetNameA VARCHAR, streetNameB VARCHAR,
    streetTypeA VARCHAR, streetTypeB VARCHAR, dirsA VARCHAR, dirsB VARCHAR,  locationA VARCHAR, locationB VARCHAR, prequalabr VARCHAR) RETURNS INTEGER
AS $_$
DECLARE
  result INTEGER := 0;
  locationWeight INTEGER := 14;
  var_verbose BOOLEAN := FALSE;
BEGIN
  IF locationA IS NOT NULL AND locationB IS NOT NULL THEN
    result := levenshtein_ignore_case(locationA, locationB);
  ELSE
    IF var_verbose THEN
      RAISE NOTICE 'rate_attributes() - Location names cannot be null!';
    END IF;
    RETURN NULL;
  END IF;
  result := result + rate_attributes($1, $2, streetNameA, streetNameB, $5, $6, $7, $8,prequalabr);
  RETURN result;
END;
$_$ LANGUAGE plpgsql IMMUTABLE;

-- rate_attributes(dirpA, dirpB, streetNameA, streetNameB, streetTypeA,
-- streetTypeB, dirsA, dirsB)
-- Rates the street based on the given attributes.  Only streetNames are
-- required.  If any others are null (either A or B) they are treated as
-- empty strings.
CREATE OR REPLACE FUNCTION rate_attributes(dirpA VARCHAR, dirpB VARCHAR, streetNameA VARCHAR, streetNameB VARCHAR,
    streetTypeA VARCHAR, streetTypeB VARCHAR, dirsA VARCHAR, dirsB VARCHAR, prequalabr VARCHAR) RETURNS INTEGER
AS $_$
DECLARE
  result INTEGER := 0;
  directionWeight INTEGER := 2;
  nameWeight INTEGER := 10;
  typeWeight INTEGER := 5;
  var_verbose BOOLEAN := false;
BEGIN
  result := result + levenshtein_ignore_case(cull_null($1), cull_null($2)) * directionWeight;
  IF var_verbose THEN
    RAISE NOTICE 'streetNameA: %, streetNameB: %', streetNameA, streetNameB;
  END IF;
  IF streetNameA IS NOT NULL AND streetNameB IS NOT NULL THEN
    -- We want to treat numeric streets that have numerics as equal
    -- and not penalize if they are spelled different e.g. have ND instead of TH
    IF NOT numeric_streets_equal(streetNameA, streetNameB) THEN
        IF prequalabr IS NOT NULL THEN
            -- If the reference address (streetNameB) has a prequalabr streetNameA (prequalabr) - note: streetNameB usually comes thru without prequalabr
            -- and the input street (streetNameA) is lacking the prequal -- only penalize a little
            result := (result + levenshtein_ignore_case( trim( trim( lower(streetNameA),lower(prequalabr) ) ), trim( trim( lower(streetNameB),lower(prequalabr) ) ) )*nameWeight*0.75 + levenshtein_ignore_case(trim(streetNameA),prequalabr || ' ' ||  streetNameB) * nameWeight*0.25)::integer;
        ELSE
            result := result + levenshtein_ignore_case(streetNameA, streetNameB) * nameWeight;
        END IF;
    ELSE
    -- Penalize for numeric streets if one is completely numeric and the other is not
    -- This is to minimize on highways like 3A being matched with numbered streets since streets are usually number followed by 2 characters e.g nth ave and highways are just number with optional letter for name
        IF  (streetNameB ~ E'[a-zA-Z]{2,10}' AND NOT (streetNameA ~ E'[a-zA-Z]{2,10}') ) OR (streetNameA ~ E'[a-zA-Z]{2,10}' AND NOT (streetNameB ~ E'[a-zA-Z]{2,10}') ) THEN
            result := result + levenshtein_ignore_case(streetNameA, streetNameB) * nameWeight;
        END IF;
    END IF;
  ELSE
    IF var_verbose THEN
      RAISE NOTICE 'rate_attributes() - Street names cannot be null!';
    END IF;
    RETURN NULL;
  END IF;
  result := result + levenshtein_ignore_case(cull_null(streetTypeA), cull_null(streetTypeB)) *
      typeWeight;
  result := result + levenshtein_ignore_case(cull_null(dirsA), cull_null(dirsB)) *
      directionWeight;
  return result;
END;
$_$ LANGUAGE plpgsql IMMUTABLE;
-- This function requires the addresses to be grouped, such that the second and
-- third arguments are from one side of the street, and the fourth and fifth
-- from the other.
CREATE OR REPLACE FUNCTION includes_address(
    given_address INTEGER,
    addr1 INTEGER,
    addr2 INTEGER,
    addr3 INTEGER,
    addr4 INTEGER
) RETURNS BOOLEAN
AS $_$
DECLARE
  lmaxaddr INTEGER := -1;
  rmaxaddr INTEGER := -1;
  lminaddr INTEGER := -1;
  rminaddr INTEGER := -1;
  maxaddr INTEGER := -1;
  minaddr INTEGER := -1;
  verbose BOOLEAN := false;
BEGIN
  IF addr1 IS NOT NULL THEN
    maxaddr := addr1;
    minaddr := addr1;
    lmaxaddr := addr1;
    lminaddr := addr1;
  END IF;

  IF addr2 IS NOT NULL THEN
    IF addr2 < minaddr OR minaddr = -1 THEN
      minaddr := addr2;
    END IF;
    IF addr2 > maxaddr OR maxaddr = -1 THEN
      maxaddr := addr2;
    END IF;
    IF addr2 > lmaxaddr OR lmaxaddr = -1 THEN
      lmaxaddr := addr2;
    END IF;
    IF addr2 < lminaddr OR lminaddr = -1 THEN
      lminaddr := addr2;
    END IF;
  END IF;

  IF addr3 IS NOT NULL THEN
    IF addr3 < minaddr OR minaddr = -1 THEN
      minaddr := addr3;
    END IF;
    IF addr3 > maxaddr OR maxaddr = -1 THEN
      maxaddr := addr3;
    END IF;
    rmaxaddr := addr3;
    rminaddr := addr3;
  END IF;

  IF addr4 IS NOT NULL THEN
    IF addr4 < minaddr OR minaddr = -1 THEN
      minaddr := addr4;
    END IF;
    IF addr4 > maxaddr OR maxaddr = -1 THEN
      maxaddr := addr4;
    END IF;
    IF addr4 > rmaxaddr OR rmaxaddr = -1 THEN
      rmaxaddr := addr4;
    END IF;
    IF addr4 < rminaddr OR rminaddr = -1 THEN
      rminaddr := addr4;
    END IF;
  END IF;

  IF minaddr = -1 OR maxaddr = -1 THEN
    -- No addresses were non-null, return FALSE (arbitrary)
    RETURN FALSE;
  ELSIF given_address >= minaddr AND given_address <= maxaddr THEN
    -- The address is within the given range
    IF given_address >= lminaddr AND given_address <= lmaxaddr THEN
      -- This checks to see if the address is on this side of the
      -- road, ie if the address is even, the street range must be even
      IF (given_address % 2) = (lminaddr % 2)
          OR (given_address % 2) = (lmaxaddr % 2) THEN
        RETURN TRUE;
      END IF;
    END IF;
    IF given_address >= rminaddr AND given_address <= rmaxaddr THEN
      -- See above
      IF (given_address % 2) = (rminaddr % 2)
          OR (given_address % 2) = (rmaxaddr % 2) THEN
        RETURN TRUE;
      END IF;
    END IF;
  END IF;
  -- The address is not within the range
  RETURN FALSE;
END;
$_$ LANGUAGE plpgsql IMMUTABLE COST 20 PARALLEL SAFE;
-- interpolate_from_address(local_address, from_address_l, to_address_l, from_address_r, to_address_r, local_road)
-- This function returns a point along the given geometry (must be linestring)
-- corresponding to the given address.  If the given address is not within
-- the address range of the road, null is returned.
-- This function requires that the address be grouped, such that the second and
-- third arguments are from one side of the street, while the fourth and
-- fifth are from the other.
-- in_side Side of street -- either 'L', 'R' or if blank ignores side of road
-- in_offset_m -- number of meters offset to the side
CREATE OR REPLACE FUNCTION interpolate_from_address(given_address INTEGER, in_addr1 VARCHAR, in_addr2 VARCHAR, in_road GEOMETRY,
	in_side VARCHAR DEFAULT '',in_offset_m float DEFAULT 10) RETURNS GEOMETRY
AS $_$
DECLARE
  addrwidth INTEGER;
  part DOUBLE PRECISION;
  road GEOMETRY;
  result GEOMETRY;
  var_addr1 INTEGER; var_addr2 INTEGER;
  center_pt GEOMETRY; cl_pt GEOMETRY;
  npos integer;
  delx float; dely float;  x0 float; y0 float; x1 float; y1 float; az float;
  var_dist float; dir integer;
BEGIN
    IF in_road IS NULL THEN
        RETURN NULL;
    END IF;

	var_addr1 := to_number( CASE WHEN in_addr1 ~ '^[0-9]+$' THEN in_addr1 ELSE '0' END, '999999');
	var_addr2 := to_number( CASE WHEN in_addr2 ~ '^[0-9]+$' THEN in_addr2 ELSE '0' END, '999999');

    IF geometrytype(in_road) = 'LINESTRING' THEN
      road := ST_Transform(in_road, utmzone(ST_StartPoint(in_road)) );
    ELSIF geometrytype(in_road) = 'MULTILINESTRING' THEN
    	road := ST_GeometryN(in_road,1);
    	road := ST_Transform(road, utmzone(ST_StartPoint(road)) );
    ELSE
      RETURN NULL;
    END IF;

    addrwidth := greatest(var_addr1,var_addr2) - least(var_addr1,var_addr2);
    IF addrwidth = 0 or addrwidth IS NULL THEN
        addrwidth = 1;
    END IF;
    part := (given_address - least(var_addr1,var_addr2)) / trunc(addrwidth, 1);

    IF var_addr1 > var_addr2 THEN
        part := 1 - part;
    END IF;

    IF part < 0 OR part > 1 OR part IS NULL THEN
        part := 0.5;
    END IF;

    center_pt = ST_LineInterpolatePoint(road, part);
    IF in_side > '' AND in_offset_m > 0 THEN
    /** Compute point the point to the in_side of the geometry **/
    /**Take into consideration non-straight so we consider azimuth
    	of the 2 points that straddle the center location**/
    	IF part = 0 THEN
    		az := ST_Azimuth (ST_StartPoint(road), ST_PointN(road,2));
    	ELSIF part = 1 THEN
    		az := ST_Azimuth (ST_PointN(road,ST_NPoints(road) - 1), ST_EndPoint(road));
    	ELSE
    		/** Find the largest nth point position that is before the center point
    			This will be the start of our azimuth calc **/
    		SELECT i INTO npos
    			FROM generate_series(1,ST_NPoints(road)) As i
    					WHERE part > ST_LineLocatePoint(road,ST_PointN(road,i))
    					ORDER BY i DESC;
    		IF npos < ST_NPoints(road) THEN
    			az := ST_Azimuth (ST_PointN(road,npos), ST_PointN(road, npos + 1));
    		ELSE
    			az := ST_Azimuth (center_pt, ST_PointN(road, npos));
    		END IF;
    	END IF;

        dir := CASE WHEN az < pi() THEN -1 ELSE 1 END;
        --dir := 1;
        var_dist := in_offset_m*CASE WHEN in_side = 'L' THEN -1 ELSE 1 END;
        delx := ABS(COS(az)) * var_dist * dir;
        dely := ABS(SIN(az)) * var_dist * dir;
        IF az > pi()/2 AND az < pi() OR az > 3 * pi()/2 THEN
			result := ST_Translate(center_pt, delx, dely) ;
		ELSE
			result := ST_Translate(center_pt, -delx, dely);
		END IF;
    ELSE
    	result := center_pt;
    END IF;
    result :=  ST_Transform(result, ST_SRID(in_road));
    --RAISE NOTICE 'start: %, center: %, new: %, side: %, offset: %, az: %', ST_AsText(ST_Transform(ST_StartPoint(road),ST_SRID(in_road))), ST_AsText(ST_Transform(center_pt,ST_SRID(in_road))),ST_AsText(result), in_side, in_offset_m, az;
    RETURN result;
END;
$_$ LANGUAGE plpgsql IMMUTABLE COST 10 PARALLEL SAFE;
-- needed to ban stupid warning about how we are using deprecated functions
-- yada yada yada need this to work in 2.0 too bah
ALTER FUNCTION interpolate_from_address(integer, character varying, character varying, geometry, character varying, double precision)
  SET client_min_messages='ERROR';
--DROP FUNCTION IF EXISTS geocode_address(norm_addy, integer , geometry);
CREATE OR REPLACE FUNCTION geocode_address(IN parsed norm_addy, max_results integer DEFAULT 10, restrict_geom geometry DEFAULT NULL, OUT addy norm_addy, OUT geomout geometry, OUT rating integer)
  RETURNS SETOF record AS
$$
DECLARE
  results RECORD;
  zip_info RECORD;
  stmt VARCHAR;
  in_statefp VARCHAR;
  exact_street boolean := false;
  var_debug boolean := get_geocode_setting('debug_geocode_address')::boolean;
  var_sql text := '';
  var_n integer := 0;
  var_restrict_geom geometry := NULL;
  var_bfilter text := null;
  var_bestrating integer := NULL;
  var_zip_penalty numeric := get_geocode_setting('zip_penalty')::numeric*1.00;
BEGIN
  IF parsed.streetName IS NULL THEN
    -- A street name must be given.  Think about it.
    RETURN;
  END IF;

  ADDY.internal := parsed.internal;

  IF parsed.stateAbbrev IS NOT NULL THEN
    in_statefp := statefp FROM state_lookup As s WHERE s.abbrev = parsed.stateAbbrev;
  END IF;

  IF in_statefp IS NULL THEN
  --if state is not provided or was bogus, just pick the first where the zip is present
    in_statefp := statefp FROM zip_lookup_base WHERE zip = substring(parsed.zip,1,5) LIMIT 1;
  END IF;

  IF restrict_geom IS NOT NULL THEN
  		IF ST_SRID(restrict_geom) < 1 OR ST_SRID(restrict_geom) = 4236 THEN
  		-- basically has no srid or if wgs84 close enough to NAD 83 -- assume same as data
  			var_restrict_geom = ST_SetSRID(restrict_geom,4269);
  		ELSE
  		--transform and snap
  			var_restrict_geom = ST_SnapToGrid(ST_Transform(restrict_geom, 4269), 0.000001);
  		END IF;
  END IF;
  var_bfilter := ' SELECT zcta5ce FROM tiger.zcta5 AS zc
                    WHERE zc.statefp = ' || quote_nullable(in_statefp) || '
                        AND ST_Intersects(zc.the_geom, ' || quote_literal(var_restrict_geom::text) || '::geometry)  ' ;

  SELECT NULL::varchar[] As zip INTO zip_info;

  IF parsed.zip IS NOT NULL  THEN
  -- Create an array of 5 zips containing 2 before and 2 after our target if our streetName is longer
    IF length(parsed.streetName) > 7 THEN
        SELECT zip_range(parsed.zip, -2, 2) As zip INTO zip_info;
    ELSE
    -- If our street name is short, we'll run into many false positives so reduce our zip window a bit
        SELECT zip_range(parsed.zip, -1, 1) As zip INTO zip_info;
    END IF;
    --This signals bad zip input, only use the range if it falls in the place zip range
    IF length(parsed.zip) != 5 AND parsed.location IS NOT NULL THEN
         stmt := 'SELECT ARRAY(SELECT DISTINCT zip
          FROM tiger.zip_lookup_base AS z
         WHERE z.statefp = $1
               AND  z.zip = ANY($3) AND lower(z.city) LIKE lower($2) || ''%''::text '  || COALESCE(' AND z.zip IN(' || var_bfilter || ')', '') || ')::varchar[] AS zip ORDER BY zip' ;
         EXECUTE stmt INTO zip_info USING in_statefp, parsed.location, zip_info.zip;
         IF var_debug THEN
            RAISE NOTICE 'Bad zip newzip range: %', quote_nullable(zip_info.zip);
         END IF;
        IF array_upper(zip_info.zip,1) = 0 OR array_upper(zip_info.zip,1) IS NULL THEN
        -- zips do not fall in city ignore them
            IF var_debug THEN
                RAISE NOTICE 'Ignore new zip range that is bad too: %', quote_nullable(zip_info.zip);
            END IF;
            zip_info.zip = NULL::varchar[];
        END IF;
    END IF;
  END IF;
  IF zip_info.zip IS NULL THEN
  -- If no good zips just include all for the location
  -- We do a like instead of absolute check since tiger sometimes tacks things like Town at end of places
    stmt := 'SELECT ARRAY(SELECT DISTINCT zip
          FROM tiger.zip_lookup_base AS z
         WHERE z.statefp = $1
               AND  lower(z.city) LIKE lower($2) || ''%''::text '  || COALESCE(' AND z.zip IN(' || var_bfilter || ')', '') || ')::varchar[] AS zip ORDER BY zip' ;
    EXECUTE stmt INTO zip_info USING in_statefp, parsed.location;
    IF var_debug THEN
        RAISE NOTICE 'Zip range based on only considering city: %', quote_nullable(zip_info.zip);
    END IF;
  END IF;
   -- Brute force -- try to find perfect matches and exit if we have one
   -- we first pull all the names in zip and rank by if zip matches input zip and streetname matches street
  stmt := 'WITH a AS
  	( SELECT *
  		FROM (SELECT f.*, ad.side, ad.zip, ad.fromhn, ad.tohn,
  					RANK() OVER(ORDER BY ' || CASE WHEN parsed.zip > '' THEN ' diff_zip(ad.zip,$7)*$11 + ' ELSE '' END
						||' CASE WHEN lower(f.name) = lower($2) THEN 0 ELSE levenshtein_ignore_case(f.name, lower($2) )  END +
						levenshtein_ignore_case(f.fullname, lower($2 || '' '' || COALESCE($4,'''')) )
						+ CASE WHEN (greatest_hn(ad.fromhn,ad.tohn) % 2)::integer = ($1 % 2)::integer THEN 0 ELSE 1 END
						+ CASE WHEN $1::integer BETWEEN least_hn(ad.fromhn,ad.tohn) AND greatest_hn(ad.fromhn, ad.tohn)
							THEN 0 ELSE 4 END
							+ CASE WHEN lower($4) = lower(f.suftypabrv) OR lower($4) = lower(f.pretypabrv) THEN 0 ELSE 1 END
							+ rate_attributes($5, f.predirabrv,'
         || '    $2,  f.name , $4,'
         || '    suftypabrv , $6,'
         || '    sufdirabrv, prequalabr)
							)
						As rank
                		FROM tiger.featnames As f INNER JOIN tiger.addr As ad ON (f.tlid = ad.tlid)
                    WHERE $10 = f.statefp AND $10 = ad.statefp
                    	'
                    || CASE WHEN length(parsed.streetName) > 5  THEN ' AND (lower(f.fullname) LIKE (COALESCE($5 || '' '','''') || lower($2) || ''%'')::text OR lower(f.name) = lower($2) OR soundex(f.name) = soundex($2) ) ' ELSE  ' AND lower(f.name) = lower($2) ' END
                    || CASE WHEN zip_info.zip IS NOT NULL THEN '    AND ( ad.zip = ANY($9::varchar[]) )  ' ELSE '' END
            || ' ) AS foo ORDER BY rank LIMIT ' || max_results*3 || ' )
  	SELECT * FROM (
    SELECT DISTINCT ON (sub.predirabrv,sub.fename,COALESCE(sub.suftypabrv, sub.pretypabrv) ,sub.sufdirabrv,sub.place,s.stusps,sub.zip)'
         || '    sub.predirabrv   as fedirp,'
         || '    sub.fename,'
         || '    COALESCE(sub.suftypabrv, sub.pretypabrv)   as fetype,'
         || '    sub.sufdirabrv   as fedirs,'
         || '    sub.place ,'
         || '    s.stusps as state,'
         || '    sub.zip as zip,'
         || '    interpolate_from_address($1, sub.fromhn,'
         || '        sub.tohn, sub.the_geom, sub.side) as address_geom,'
         || '       (sub.sub_rating + '
         || CASE WHEN parsed.zip > '' THEN '  least(coalesce(diff_zip($7 , sub.zip),0), 20)*$11  '
            ELSE '1' END::text
         || ' + coalesce(levenshtein_ignore_case($3, sub.place),5) )::integer'
         || '    as sub_rating,'
         || '    sub.exact_address as exact_address, sub.tohn, sub.fromhn '
         || ' FROM ('
         || '  SELECT tlid, predirabrv, COALESCE(b.prequalabr || '' '','''' ) || b.name As fename, suftypabrv, sufdirabrv, fromhn, tohn,
                    side,  zip, rate_attributes($5, predirabrv,'
         || '    $2,  b.name , $4,'
         || '    suftypabrv , $6,'
         || '    sufdirabrv, prequalabr) + '
         || '    CASE '
         || '        WHEN $1::integer IS NULL OR b.fromhn IS NULL THEN 20'
         || '        WHEN $1::integer >= least_hn(b.fromhn, b.tohn) '
         || '            AND $1::integer <= greatest_hn(b.fromhn,b.tohn)'
         || '            AND ($1::integer % 2) = (to_number(b.fromhn,''99999999'') % 2)::integer'
         || '            THEN 0'
         || '        WHEN $1::integer >= least_hn(b.fromhn,b.tohn)'
         || '            AND $1::integer <= greatest_hn(b.fromhn,b.tohn)'
         || '            THEN 2'
         || '        ELSE'
         || '            ((1.0 - '
         ||              '(least_hn($1::text,least_hn(b.fromhn,b.tohn)::text)::numeric /'
         ||              ' (greatest(1,greatest_hn($1::text,greatest_hn(b.fromhn,b.tohn)::text))) )'
         ||              ') * 5)::integer + 5'
         || '        END::integer'
         || '    AS sub_rating,$1::integer >= least_hn(b.fromhn,b.tohn) '
         || '            AND $1::integer <= greatest_hn(b.fromhn,b.tohn) '
         || '            AND ($1 % 2)::numeric::integer = (to_number(b.fromhn,''99999999'') % 2)'
         || '    as exact_address, b.name, b.prequalabr, b.pretypabrv, b.tfidr, b.tfidl, b.the_geom, b.place '
         || '  FROM
             (SELECT   a.tlid, a.fullname, a.name, a.predirabrv, a.suftypabrv, a.sufdirabrv, a.prequalabr, a.pretypabrv,
                b.the_geom, tfidr, tfidl,
                a.side ,
                a.fromhn,
                a.tohn,
                a.zip,
                p.name as place

                FROM  a INNER JOIN tiger.edges As b ON (a.statefp = b.statefp AND a.tlid = b.tlid  '
               || ')
                    INNER JOIN tiger.faces AS f ON ($10 = f.statefp AND ( (b.tfidl = f.tfid AND a.side = ''L'') OR (b.tfidr = f.tfid AND a.side = ''R'' ) ))
                    INNER JOIN tiger.place p ON ($10 = p.statefp AND f.placefp = p.placefp '
          || CASE WHEN parsed.location > '' AND zip_info.zip IS NULL THEN ' AND ( lower(p.name) LIKE (lower($3::text) || ''%'')  ) ' ELSE '' END
          || ')
                WHERE a.statefp = $10  AND  b.statefp = $10   '
             ||   CASE WHEN var_restrict_geom IS NOT NULL THEN ' AND ST_Intersects(b.the_geom, $8::geometry) '  ELSE '' END
             || '

          )   As b
           ORDER BY 10 ,  11 DESC
           LIMIT 20
            ) AS sub
          JOIN tiger.state s ON ($10 = s.statefp)
            ORDER BY 1,2,3,4,5,6,7,9
          LIMIT 20) As foo ORDER BY sub_rating, exact_address DESC LIMIT  ' || max_results*10 ;

  IF var_debug THEN
         RAISE NOTICE 'stmt: %',
            replace( replace( replace(
                replace(
                replace(replace( replace(replace(replace(replace( replace(stmt,'$11', var_zip_penalty::text), '$10', quote_nullable(in_statefp) ), '$2',quote_nullable(parsed.streetName)),'$3',
                quote_nullable(parsed.location)), '$4', quote_nullable(parsed.streetTypeAbbrev) ),
                '$5', quote_nullable(parsed.preDirAbbrev) ),
                   '$6', quote_nullable(parsed.postDirAbbrev) ),
                   '$7', quote_nullable(parsed.zip) ),
                   '$8', quote_nullable(var_restrict_geom::text) ),
                   '$9', quote_nullable(zip_info.zip) ), '$1', quote_nullable(parsed.address) );
        --RAISE NOTICE 'PREPARE query_base_geo(integer, varchar,varchar,varchar,varchar,varchar,varchar,geometry,varchar[]) As %', stmt;
        --RAISE NOTICE 'EXECUTE query_base_geo(%,%,%,%,%,%,%,%,%); ', parsed.address,quote_nullable(parsed.streetName), quote_nullable(parsed.location), quote_nullable(parsed.streetTypeAbbrev), quote_nullable(parsed.preDirAbbrev), quote_nullable(parsed.postDirAbbrev), quote_nullable(parsed.zip), quote_nullable(var_restrict_geom::text), quote_nullable(zip_info.zip);
        --RAISE NOTICE 'DEALLOCATE query_base_geo;';
    END IF;
    FOR results IN EXECUTE stmt USING parsed.address,parsed.streetName, parsed.location, parsed.streetTypeAbbrev, parsed.preDirAbbrev, parsed.postDirAbbrev, parsed.zip, var_restrict_geom, zip_info.zip, in_statefp, var_zip_penalty LOOP

        -- If we found a match with an exact street, then don't bother
        -- trying to do non-exact matches

        exact_street := true;

        IF results.exact_address THEN
            ADDY.address := parsed.address;
        ELSE
            ADDY.address := CASE WHEN parsed.address > to_number(results.tohn,'99999999') AND parsed.address > to_number(results.fromhn, '99999999') THEN greatest_hn(results.fromhn, results.tohn)::integer
                ELSE least_hn(results.fromhn, results.tohn)::integer END ;
        END IF;

        ADDY.preDirAbbrev     := results.fedirp;
        ADDY.streetName       := results.fename;
        ADDY.streetTypeAbbrev := results.fetype;
        ADDY.postDirAbbrev    := results.fedirs;
        ADDY.location         := results.place;
        ADDY.stateAbbrev      := results.state;
        ADDY.zip              := results.zip;
        ADDY.parsed := TRUE;

        GEOMOUT := results.address_geom;
        RATING := results.sub_rating::integer;
        var_n := var_n + 1;

        IF var_bestrating IS NULL THEN
            var_bestrating := RATING; /** the first record to come is our best rating we will ever get **/
        END IF;

        -- Only consider matches with decent ratings
        IF RATING < 90 THEN
            RETURN NEXT;
        END IF;

        -- If we get an exact match, then just return that
        IF RATING = 0 THEN
            RETURN;
        END IF;

        IF var_n >= max_results AND RATING < 10  THEN --we have exceeded our desired limit and rating is not horrible
            RETURN;
        END IF;

    END LOOP;

    IF var_bestrating < 30 THEN --if we already have a match with a rating of 30 or less, its unlikely we can do any better
        RETURN;
    END IF;

-- There are a couple of different things to try, from the highest preference and falling back
  -- to lower-preference options.
  -- We start out with zip-code matching, where the zip code could possibly be in more than one
  -- state.  We loop through each state its in.
  -- Next, we try to find the location in our side-table, which is based off of the 'place' data exact first then sounds like
  -- Next, we look up the location/city and use the zip code which is returned from that
  -- Finally, if we didn't get a zip code or a city match, we fall back to just a location/street
  -- lookup to try and find *something* useful.
  -- In the end, we *have* to find a statefp, one way or another.
  var_sql :=
  ' SELECT statefp,location,a.zip,exact,min(pref) FROM
    (SELECT zip_state.statefp as statefp,$1 as location, true As exact, ARRAY[zip_state.zip] as zip,1 as pref
        FROM zip_state WHERE zip_state.zip = $2
            AND (' || quote_nullable(in_statefp) || ' IS NULL OR zip_state.statefp = ' || quote_nullable(in_statefp) || ')
          ' || COALESCE(' AND zip_state.zip IN(' || var_bfilter || ')', '') ||
        ' UNION SELECT zip_state_loc.statefp,zip_state_loc.place As location,false As exact, array_agg(zip_state_loc.zip) AS zip,1 + abs(COALESCE(diff_zip(max(zip), $2),0) - COALESCE(diff_zip(min(zip), $2),0))*$3 As pref
              FROM zip_state_loc
             WHERE zip_state_loc.statefp = ' || quote_nullable(in_statefp) || '
                   AND lower($1) = lower(zip_state_loc.place) '  || COALESCE(' AND zip_state_loc.zip IN(' || var_bfilter || ')', '') ||
        '     GROUP BY zip_state_loc.statefp,zip_state_loc.place
      UNION SELECT zip_state_loc.statefp,zip_state_loc.place As location,false As exact, array_agg(zip_state_loc.zip),3
              FROM zip_state_loc
             WHERE zip_state_loc.statefp = ' || quote_nullable(in_statefp) || '
                   AND soundex($1) = soundex(zip_state_loc.place)
             GROUP BY zip_state_loc.statefp,zip_state_loc.place
      UNION SELECT zip_lookup_base.statefp,zip_lookup_base.city As location,false As exact, array_agg(zip_lookup_base.zip),4
              FROM zip_lookup_base
             WHERE zip_lookup_base.statefp = ' || quote_nullable(in_statefp) || '
                         AND (soundex($1) = soundex(zip_lookup_base.city) OR soundex($1) = soundex(zip_lookup_base.county))
             GROUP BY zip_lookup_base.statefp,zip_lookup_base.city
      UNION SELECT ' || quote_nullable(in_statefp) || ' As statefp,$1 As location,false As exact,NULL, 5) as a '
      ' WHERE a.statefp IS NOT NULL
      GROUP BY statefp,location,a.zip,exact, pref ORDER BY exact desc, pref, zip';
  /** FOR zip_info IN     SELECT statefp,location,zip,exact,min(pref) FROM
    (SELECT zip_state.statefp as statefp,parsed.location as location, true As exact, ARRAY[zip_state.zip] as zip,1 as pref
        FROM zip_state WHERE zip_state.zip = parsed.zip
            AND (in_statefp IS NULL OR zip_state.statefp = in_statefp)
        UNION SELECT zip_state_loc.statefp,parsed.location,false As exact, array_agg(zip_state_loc.zip),2 + diff_zip(zip[1], parsed.zip)
              FROM zip_state_loc
             WHERE zip_state_loc.statefp = in_statefp
                   AND lower(parsed.location) = lower(zip_state_loc.place)
             GROUP BY zip_state_loc.statefp,parsed.location
      UNION SELECT zip_state_loc.statefp,parsed.location,false As exact, array_agg(zip_state_loc.zip),3
              FROM zip_state_loc
             WHERE zip_state_loc.statefp = in_statefp
                   AND soundex(parsed.location) = soundex(zip_state_loc.place)
             GROUP BY zip_state_loc.statefp,parsed.location
      UNION SELECT zip_lookup_base.statefp,parsed.location,false As exact, array_agg(zip_lookup_base.zip),4
              FROM zip_lookup_base
             WHERE zip_lookup_base.statefp = in_statefp
                         AND (soundex(parsed.location) = soundex(zip_lookup_base.city) OR soundex(parsed.location) = soundex(zip_lookup_base.county))
             GROUP BY zip_lookup_base.statefp,parsed.location
      UNION SELECT in_statefp,parsed.location,false As exact,NULL, 5) as a
        --JOIN (VALUES (true),(false)) as b(exact) on TRUE
      WHERE statefp IS NOT NULL
      GROUP BY statefp,location,zip,exact, pref ORDER BY exact desc, pref, zip  **/
  FOR zip_info IN EXECUTE var_sql USING parsed.location, parsed.zip, var_zip_penalty  LOOP
  -- For zip distance metric we consider both the distance of zip based on numeric as well aa levenshtein
  -- We use the prequalabr (these are like Old, that may or may not appear in front of the street name)
  -- We also treat pretypabr as fetype since in normalize we treat these as streetypes  and highways usually have the type here
  -- In pprint_addy we changed to put it in front if it is a is_hw type
    stmt := 'SELECT DISTINCT ON (sub.predirabrv,sub.fename,COALESCE(sub.suftypabrv, sub.pretypabrv) ,sub.sufdirabrv,coalesce(p.name,cs.name,zip.city,co.name),s.stusps,sub.zip)'
         || '    sub.predirabrv   as fedirp,'
         || '    sub.fename,'
         || '    COALESCE(sub.suftypabrv, sub.pretypabrv)   as fetype,'
         || '    sub.sufdirabrv   as fedirs,'
         || '    coalesce(p.name,cs.name,zip.city,co.name)::varchar as place,'
         || '    s.stusps as state,'
         || '    sub.zip as zip,'
         || '    interpolate_from_address($1, sub.fromhn,'
         || '        sub.tohn, e.the_geom, sub.side) as address_geom,'
         || '       (sub.sub_rating + '
         || CASE WHEN parsed.zip > '' THEN '  least((coalesce(diff_zip($7 , sub.zip),0) *$9)::integer, coalesce(levenshtein_ignore_case($7, sub.zip)*$9,0) ) '
            ELSE '3' END::text
         || ' + coalesce(least(levenshtein_ignore_case($3, coalesce(p.name,cs.name,zip.city,co.name)), levenshtein_ignore_case($3, coalesce(cs.name,co.name))),5) )::integer'
         || '    as sub_rating,'
         || '    sub.exact_address as exact_address '
         || ' FROM ('
         || '  SELECT a.tlid, predirabrv, COALESCE(a.prequalabr || '' '','''' ) || a.name As fename, suftypabrv, sufdirabrv, fromhn, tohn,
                    side, a.statefp, zip, rate_attributes($5, a.predirabrv,'
         || '    $2,  a.name , $4,'
         || '    a.suftypabrv , $6,'
         || '    a.sufdirabrv, a.prequalabr) + '
         || '    CASE '
         || '        WHEN $1::integer IS NULL OR b.fromhn IS NULL THEN 20'
         || '        WHEN $1::integer >= least_hn(b.fromhn, b.tohn) '
         || '            AND $1::integer <= greatest_hn(b.fromhn,b.tohn)'
         || '            AND ($1::integer % 2) = (to_number(b.fromhn,''99999999'') % 2)::integer'
         || '            THEN 0'
         || '        WHEN $1::integer >= least_hn(b.fromhn,b.tohn)'
         || '            AND $1::integer <= greatest_hn(b.fromhn,b.tohn)'
         || '            THEN 2'
         || '        ELSE'
         || '            ((1.0 - '
         ||              '(least_hn($1::text,least_hn(b.fromhn,b.tohn)::text)::numeric /'
         ||              ' greatest(1,greatest_hn($1::text,greatest_hn(b.fromhn,b.tohn)::text)))'
         ||              ') * 5)::integer + 5'
         || '        END'
         || '    as sub_rating,$1::integer >= least_hn(b.fromhn,b.tohn) '
         || '            AND $1::integer <= greatest_hn(b.fromhn,b.tohn) '
         || '            AND ($1 % 2)::numeric::integer = (to_number(b.fromhn,''99999999'') % 2)'
         || '    as exact_address, a.name, a.prequalabr, a.pretypabrv '
         || '  FROM tiger.featnames a join tiger.addr b ON (a.tlid = b.tlid AND a.statefp = b.statefp  )'
         || '  WHERE'
         || '        a.statefp = ' || quote_literal(zip_info.statefp) || ' AND a.mtfcc LIKE ''S%''  '
         || coalesce('    AND b.zip IN (''' || array_to_string(zip_info.zip,''',''') || ''') ','')
         || CASE WHEN zip_info.exact
                 THEN '    AND ( lower($2) = lower(a.name) OR  ( a.prequalabr > '''' AND trim(lower($2), lower(a.prequalabr) || '' '') = lower(a.name) ) OR numeric_streets_equal($2, a.name) ) '
                 ELSE '    AND ( soundex($2) = soundex(a.name)  OR ( (length($2) > 15 or (length($2) > 7 AND a.prequalabr > '''') ) AND lower(a.fullname) LIKE lower(substring($2,1,15)) || ''%'' ) OR  numeric_streets_equal($2, a.name) ) '
            END
         || '  ORDER BY 11'
         || '  LIMIT 200'
         || '    ) AS sub'
         || '  JOIN tiger.edges e ON (' || quote_literal(zip_info.statefp) || ' = e.statefp AND sub.tlid = e.tlid AND e.mtfcc LIKE ''S%'' '
         ||   CASE WHEN var_restrict_geom IS NOT NULL THEN ' AND ST_Intersects(e.the_geom, $8) '  ELSE '' END || ') '
         || '  JOIN tiger.state s ON (' || quote_literal(zip_info.statefp) || ' = s.statefp)'
         || '  JOIN tiger.faces f ON (' || quote_literal(zip_info.statefp) || ' = f.statefp AND (e.tfidl = f.tfid OR e.tfidr = f.tfid))'
         || '  LEFT JOIN tiger.zip_lookup_base zip ON (sub.zip = zip.zip AND zip.statefp=' || quote_literal(zip_info.statefp) || ')'
         || '  LEFT JOIN tiger.place p ON (' || quote_literal(zip_info.statefp) || ' = p.statefp AND f.placefp = p.placefp)'
         || '  LEFT JOIN tiger.county co ON (' || quote_literal(zip_info.statefp) || ' = co.statefp AND f.countyfp = co.countyfp)'
         || '  LEFT JOIN tiger.cousub cs ON (' || quote_literal(zip_info.statefp) || ' = cs.statefp AND cs.cosbidfp = sub.statefp || co.countyfp || f.cousubfp)'
         || ' WHERE'
         || '  ( (sub.side = ''L'' and e.tfidl = f.tfid) OR (sub.side = ''R'' and e.tfidr = f.tfid) ) '
         || ' ORDER BY 1,2,3,4,5,6,7,9'
         || ' LIMIT 10'
         ;
    IF var_debug THEN
        RAISE NOTICE '%', stmt;
        RAISE NOTICE 'PREPARE query_base_geo(integer, varchar,varchar,varchar,varchar,varchar,varchar,geometry,numeric) As %', stmt;
        RAISE NOTICE 'EXECUTE query_base_geo(%,%,%,%,%,%,%,%,%); ', parsed.address,quote_nullable(parsed.streetName), quote_nullable(parsed.location), quote_nullable(parsed.streetTypeAbbrev), quote_nullable(parsed.preDirAbbrev), quote_nullable(parsed.postDirAbbrev), quote_nullable(parsed.zip), quote_nullable(var_restrict_geom::text), quote_nullable(var_zip_penalty);
        RAISE NOTICE 'DEALLOCATE query_base_geo;';
    END IF;
    -- If we got an exact street match then when we hit the non-exact
    -- set of tests, just drop out.
    IF NOT zip_info.exact AND exact_street THEN
        RETURN;
    END IF;

    FOR results IN EXECUTE stmt USING parsed.address,parsed.streetName, parsed.location, parsed.streetTypeAbbrev, parsed.preDirAbbrev, parsed.postDirAbbrev, parsed.zip, var_restrict_geom, var_zip_penalty LOOP

      -- If we found a match with an exact street, then don't bother
      -- trying to do non-exact matches
      IF zip_info.exact THEN
        exact_street := true;
      END IF;

      IF results.exact_address THEN
        ADDY.address := substring(parsed.address::text FROM '[0-9]+')::integer;
      ELSE
        ADDY.address := NULL;
      END IF;

      ADDY.preDirAbbrev     := results.fedirp;
      ADDY.streetName       := results.fename;
      ADDY.streetTypeAbbrev := results.fetype;
      ADDY.postDirAbbrev    := results.fedirs;
      ADDY.location         := results.place;
      ADDY.stateAbbrev      := results.state;
      ADDY.zip              := results.zip;
      ADDY.parsed := TRUE;

      GEOMOUT := results.address_geom;
      RATING := results.sub_rating::integer;
      var_n := var_n + 1;

      -- If our ratings go above 99 exit because its a really bad match
      IF RATING > 99 THEN
        RETURN;
      END IF;

      RETURN NEXT;

      -- If we get an exact match, then just return that
      IF RATING = 0 THEN
        RETURN;
      END IF;

    END LOOP;
    IF var_n > max_results  THEN --we have exceeded our desired limit
        RETURN;
    END IF;
  END LOOP;

  RETURN;
END;
$$
  LANGUAGE 'plpgsql' STABLE COST 1000 ROWS 50 PARALLEL SAFE;

CREATE OR REPLACE FUNCTION geocode_location(
    parsed NORM_ADDY,
    restrict_geom geometry DEFAULT null,
    OUT ADDY NORM_ADDY,
    OUT GEOMOUT GEOMETRY,
    OUT RATING INTEGER
) RETURNS SETOF RECORD
AS $_$
DECLARE
  result RECORD;
  in_statefp VARCHAR;
  stmt VARCHAR;
  var_debug boolean := false;
BEGIN

  in_statefp := statefp FROM state WHERE state.stusps = parsed.stateAbbrev;

  IF var_debug THEN
    RAISE NOTICE 'geocode_location starting: %', clock_timestamp();
  END IF;
  FOR result IN
    SELECT
        coalesce(zip.city)::varchar as place,
        zip.zip as zip,
        ST_Centroid(zcta5.the_geom) as address_geom,
        stusps as state,
        100::integer + coalesce(levenshtein_ignore_case(coalesce(zip.city), parsed.location),0) as in_rating
    FROM
      zip_lookup_base zip
      JOIN zcta5 ON (zip.zip = zcta5.zcta5ce AND zip.statefp = zcta5.statefp)
      JOIN state ON (state.statefp=zip.statefp)
    WHERE
      parsed.zip = zip.zip OR
      (soundex(zip.city) = soundex(parsed.location) and zip.statefp = in_statefp)
    ORDER BY levenshtein_ignore_case(coalesce(zip.city), parsed.location), zip.zip
  LOOP
    ADDY.location := result.place;
    ADDY.stateAbbrev := result.state;
    ADDY.zip := result.zip;
    ADDY.parsed := true;
    GEOMOUT := result.address_geom;
    RATING := result.in_rating;

    RETURN NEXT;

    IF RATING = 100 THEN
      RETURN;
    END IF;

  END LOOP;

  IF parsed.location IS NULL THEN
    parsed.location := city FROM zip_lookup_base WHERE zip_lookup_base.zip = parsed.zip ORDER BY zip_lookup_base.zip LIMIT 1;
    in_statefp := statefp FROM zip_lookup_base WHERE zip_lookup_base.zip = parsed.zip ORDER BY zip_lookup_base.zip LIMIT 1;
  END IF;

  stmt := 'SELECT '
       || ' pl.name as place, '
       || ' state.stusps as stateAbbrev, '
       || ' ST_Centroid(pl.the_geom) as address_geom, '
       || ' 100::integer + levenshtein_ignore_case(coalesce(pl.name), ' || quote_literal(coalesce(parsed.location,'')) || ') as in_rating '
       || ' FROM (SELECT * FROM place WHERE statefp = ' ||  quote_literal(coalesce(in_statefp,'')) || ' ' || COALESCE(' AND ST_Intersects(' || quote_literal(restrict_geom::text) || '::geometry, the_geom)', '') || ') AS pl '
       || ' INNER JOIN state ON(pl.statefp = state.statefp)'
       || ' WHERE soundex(pl.name) = soundex(' || quote_literal(coalesce(parsed.location,'')) || ') and pl.statefp = ' || quote_literal(COALESCE(in_statefp,''))
       || ' ORDER BY levenshtein_ignore_case(coalesce(pl.name), ' || quote_literal(coalesce(parsed.location,'')) || ');'
       ;

  IF var_debug THEN
    RAISE NOTICE 'geocode_location stmt: %', stmt;
  END IF;
  FOR result IN EXECUTE stmt
  LOOP

    ADDY.location := result.place;
    ADDY.stateAbbrev := result.stateAbbrev;
    ADDY.zip = parsed.zip;
    ADDY.parsed := true;
    GEOMOUT := result.address_geom;
    RATING := result.in_rating;

    RETURN NEXT;

    IF RATING = 100 THEN
      RETURN;
      IF var_debug THEN
        RAISE NOTICE 'geocode_location ending hit 100 rating result: %', clock_timestamp();
      END IF;
    END IF;
  END LOOP;

  IF var_debug THEN
    RAISE NOTICE 'geocode_location ending: %', clock_timestamp();
  END IF;

  RETURN;

END;
$_$ LANGUAGE plpgsql STABLE COST 20  ROWS 5 PARALLEL SAFE;
 /***
 *
 * Copyright (C) 2011-2016 Regina Obe and Leo Hsu (Paragon Corporation)
 **/
-- This function given two roadways, state and optional city, zip
-- Will return addresses that are at the intersection of those roadways
-- The address returned will be the address on the first road way
-- Use case example an address at the intersection of 2 streets:
-- SELECT pprint_addy(addy), st_astext(geomout),rating FROM geocode_intersection('School St', 'Washington St', 'MA', 'Boston','02117');
--DROP FUNCTION tiger.geocode_intersection(text,text,text,text,text,integer);
CREATE OR REPLACE FUNCTION geocode_intersection(
    IN roadway1 text,
    IN roadway2 text,
    IN in_state text,
    IN in_city text DEFAULT ''::text,
    IN in_zip text DEFAULT ''::text,
    IN num_results integer DEFAULT 10,
    OUT addy norm_addy,
    OUT geomout geometry,
    OUT rating integer)
  RETURNS SETOF record AS
$$
DECLARE
    var_na_road norm_addy;
    var_na_inter1 norm_addy;
    var_sql text := '';
    var_zip varchar(5)[];
    in_statefp varchar(2) ;
    var_debug boolean := get_geocode_setting('debug_geocode_intersection')::boolean;
    results record;
BEGIN
    IF COALESCE(roadway1,'') = '' OR COALESCE(roadway2,'') = '' THEN
        -- not enough to give a result just return
        RETURN ;
    ELSE
        var_na_road := normalize_address('0 ' || roadway1 || ', ' || COALESCE(in_city,'') || ', ' || in_state || ' ' || in_zip);
        var_na_inter1  := normalize_address('0 ' || roadway2 || ', ' || COALESCE(in_city,'') || ', ' || in_state || ' ' || in_zip);
    END IF;
    in_statefp := statefp FROM state_lookup As s WHERE s.abbrev = upper(in_state);
    IF COALESCE(in_zip,'') > '' THEN -- limit search to 2 plus or minus the input zip
        var_zip := zip_range(in_zip, -2,2);
    END IF;

    IF var_zip IS NULL AND in_city > '' THEN
        var_zip := array_agg(zip) FROM zip_lookup_base WHERE statefp = in_statefp AND lower(city) = lower(in_city);
    END IF;

    -- if we don't have a city or zip, don't bother doing the zip check, just keep as null
    IF var_zip IS NULL AND in_city > '' THEN
        var_zip := array_agg(zip) FROM zip_lookup_base WHERE statefp = in_statefp AND lower(city) LIKE lower(in_city) || '%'  ;
    END IF;
    IF var_debug THEN
		RAISE NOTICE 'var_zip: %, city: %', quote_nullable(var_zip), quote_nullable(in_city);
    END IF;
    var_sql := '
    WITH
    	a1 AS (SELECT f.*, addr.fromhn, addr.tohn, addr.side , addr.zip
    				FROM (SELECT * FROM tiger.featnames
    							WHERE statefp = $1 AND ( lower(name) = $2  ' ||
    							CASE WHEN length(var_na_road.streetName) > 5 THEN ' or  lower(fullname) LIKE $6 || ''%'' ' ELSE '' END || ')'
    							|| ')  AS f LEFT JOIN (SELECT * FROM tiger.addr As addr WHERE addr.statefp = $1) As addr ON (addr.tlid = f.tlid AND addr.statefp = f.statefp)
    					WHERE $5::text[] IS NULL OR addr.zip = ANY($5::text[]) OR addr.zip IS NULL
    				ORDER BY CASE WHEN lower(f.fullname) = $6 THEN 0 ELSE 1 END
    				LIMIT 50000
    			  ),
        a2 AS (SELECT f.*, addr.fromhn, addr.tohn, addr.side , addr.zip
    				FROM (SELECT * FROM tiger.featnames
    							WHERE statefp = $1 AND ( lower(name) = $4 ' ||
    							CASE WHEN length(var_na_inter1.streetName) > 5 THEN ' or lower(fullname) LIKE $7 || ''%'' ' ELSE '' END || ')'
    							|| ' )  AS f LEFT JOIN (SELECT * FROM tiger.addr As addr WHERE addr.statefp = $1) AS addr ON (addr.tlid = f.tlid AND addr.statefp = f.statefp)
    					WHERE $5::text[] IS NULL OR addr.zip = ANY($5::text[])  or addr.zip IS NULL
    			ORDER BY CASE WHEN lower(f.fullname) = $7 THEN 0 ELSE 1 END
    				LIMIT 50000
    			  ),
    	 e1 AS (SELECT e.the_geom, e.tnidf, e.tnidt, a.*,
    	 			CASE WHEN a.side = ''L'' THEN e.tfidl ELSE e.tfidr END AS tfid
    	 			FROM a1 As a
    					INNER JOIN  tiger.edges AS e ON (e.statefp = a.statefp AND a.tlid = e.tlid)
    				WHERE e.statefp = $1
    				ORDER BY CASE WHEN lower(a.name) = $4 THEN 0 ELSE 1 END + CASE WHEN lower(e.fullname) = $7 THEN 0 ELSE 1 END
    				LIMIT 5000) ,
    	e2 AS (SELECT e.the_geom, e.tnidf, e.tnidt, a.*,
    	 			CASE WHEN a.side = ''L'' THEN e.tfidl ELSE e.tfidr END AS tfid
    				FROM (SELECT * FROM tiger.edges WHERE statefp = $1) AS e INNER JOIN a2 AS a ON (e.statefp = a.statefp AND a.tlid = e.tlid)
    					INNER JOIN e1 ON (e.statefp = e1.statefp
    					AND ARRAY[e.tnidf, e.tnidt] && ARRAY[e1.tnidf, e1.tnidt] )

    				WHERE (lower(e.fullname) = $7 or lower(a.name) LIKE $4 || ''%'')
    				ORDER BY CASE WHEN lower(a.name) = $4 THEN 0 ELSE 1 END + CASE WHEN lower(e.fullname) = $7 THEN 0 ELSE 1 END
    				LIMIT 5000
    				),
    	segs AS (SELECT DISTINCT ON(e1.tlid, e1.side)
                   CASE WHEN e1.tnidf = e2.tnidf OR e1.tnidf = e2.tnidt THEN
                                e1.fromhn
                            ELSE
                                e1.tohn END As address, e1.predirabrv As fedirp, COALESCE(e1.prequalabr || '' '','''' ) || e1.name As fename,
                             COALESCE(e1.suftypabrv,e1.pretypabrv)  As fetype, e1.sufdirabrv AS fedirs,
                               p.name As place, e1.zip,
                             CASE WHEN e1.tnidf = e2.tnidf OR e1.tnidf = e2.tnidt THEN
                                ST_StartPoint(ST_GeometryN(ST_Multi(e1.the_geom),1))
                             ELSE ST_EndPoint(ST_GeometryN(ST_Multi(e1.the_geom),1)) END AS geom ,
                                CASE WHEN lower(p.name) = $3 THEN 0 ELSE 1 END
                                + levenshtein_ignore_case(p.name, $3)
                                + levenshtein_ignore_case(e1.name || COALESCE('' '' || e1.sufqualabr, ''''),$2) +
                                CASE WHEN e1.fullname = $6 THEN 0 ELSE levenshtein_ignore_case(e1.fullname, $6) END +
                                + levenshtein_ignore_case(e2.name || COALESCE('' '' || e2.sufqualabr, ''''),$4)
                                AS a_rating
                    FROM e1
                            INNER JOIN e2 ON (
                                  ARRAY[e2.tnidf, e2.tnidt] && ARRAY[e1.tnidf, e1.tnidt]  )
                             INNER JOIN (SELECT * FROM tiger.faces WHERE statefp = $1) As fa1 ON (e1.tfid = fa1.tfid  )
                          LEFT JOIN tiger.place AS p ON (fa1.placefp = p.placefp AND p.statefp = $1 )
                       ORDER BY e1.tlid, e1.side, a_rating LIMIT $9*4 )
    SELECT address, fedirp , fename, fetype,fedirs,place, zip , geom, a_rating
        FROM segs ORDER BY a_rating LIMIT  $9';

    IF var_debug THEN
        RAISE NOTICE 'sql: %', replace(replace(replace(
        	replace(replace(replace(
                replace(
                    replace(
                        replace(var_sql, '$1', quote_nullable(in_statefp)),
                              '$2', quote_nullable(lower(var_na_road.streetName) ) ),
                      '$3', quote_nullable(lower(in_city)) ),
                      '$4', quote_nullable(lower(var_na_inter1.streetName) ) ),
                      '$5', quote_nullable(var_zip) ),
                      '$6', quote_nullable(lower(var_na_road.streetName || ' ' || COALESCE(var_na_road.streetTypeAbbrev,'') )) ) ,
                      '$7', quote_nullable(trim(lower(var_na_inter1.streetName || ' ' || COALESCE(var_na_inter1.streetTypeAbbrev,'') )) ) ) ,
		 '$8', quote_nullable(in_state ) ),  '$9', num_results::text );
    END IF;

    FOR results IN EXECUTE var_sql USING in_statefp, trim(lower(var_na_road.streetName)), lower(in_city), lower(var_na_inter1.streetName), var_zip,
		trim(lower(var_na_road.streetName || ' ' || COALESCE(var_na_road.streetTypeAbbrev,''))),
		trim(lower(var_na_inter1.streetName || ' ' || COALESCE(var_na_inter1.streetTypeAbbrev,''))), in_state, num_results LOOP
		ADDY.preDirAbbrev     := results.fedirp;
        ADDY.streetName       := results.fename;
        ADDY.streetTypeAbbrev := results.fetype;
        ADDY.postDirAbbrev    := results.fedirs;
        ADDY.location         := results.place;
        ADDY.stateAbbrev      := in_state;
        ADDY.zip              := results.zip;
        ADDY.parsed := TRUE;
        ADDY.address := substring(results.address FROM '[0-9]+')::integer;

        GEOMOUT := results.geom;
        RATING := results.a_rating;
		RETURN NEXT;
	END LOOP;
	RETURN;
END;
$$
  LANGUAGE plpgsql IMMUTABLE
  COST 1000
  ROWS 10;
ALTER FUNCTION geocode_intersection(text, text, text, text, text, integer) SET join_collapse_limit='2';
CREATE OR REPLACE FUNCTION geocode(
    input VARCHAR, max_results integer DEFAULT 10,
    restrict_geom geometry DEFAULT NULL,
    OUT ADDY NORM_ADDY,
    OUT GEOMOUT GEOMETRY,
    OUT RATING INTEGER
) RETURNS SETOF RECORD
AS $_$
DECLARE
  rec RECORD;
BEGIN

  IF input IS NULL THEN
    RETURN;
  END IF;

  -- Pass the input string into the address normalizer
  ADDY := normalize_address(input);
  IF NOT ADDY.parsed THEN
    RETURN;
  END IF;

/*  FOR rec IN SELECT * FROM geocode(ADDY)
  LOOP

    ADDY := rec.addy;
    GEOMOUT := rec.geomout;
    RATING := rec.rating;

    RETURN NEXT;
  END LOOP;*/

  RETURN QUERY SELECT g.addy, g.geomout, g.rating FROM geocode(ADDY, max_results, restrict_geom) As g ORDER BY g.rating;

END;
$_$ LANGUAGE plpgsql COST 1000
STABLE PARALLEL SAFE
ROWS 1;

CREATE OR REPLACE FUNCTION geocode(
    IN_ADDY NORM_ADDY,
    max_results integer DEFAULT 10,
    restrict_geom geometry DEFAULT null,
    OUT ADDY NORM_ADDY,
    OUT GEOMOUT GEOMETRY,
    OUT RATING INTEGER
) RETURNS SETOF RECORD
AS $_$
DECLARE
  rec RECORD;
BEGIN

  IF NOT IN_ADDY.parsed THEN
    RETURN;
  END IF;

  -- Go for the full monty if we've got enough info
  IF IN_ADDY.streetName IS NOT NULL AND
      (IN_ADDY.zip IS NOT NULL OR IN_ADDY.stateAbbrev IS NOT NULL) THEN

    FOR rec IN
        SELECT *
        FROM
          (SELECT
            DISTINCT ON (
              (a.addy).address,
              (a.addy).predirabbrev,
              (a.addy).streetname,
              (a.addy).streettypeabbrev,
              (a.addy).postdirabbrev,
              (a.addy).internal,
              (a.addy).location,
              (a.addy).stateabbrev,
              (a.addy).zip
              )
            *
           FROM
             tiger.geocode_address(IN_ADDY, max_results, restrict_geom) a
           ORDER BY
              (a.addy).address,
              (a.addy).predirabbrev,
              (a.addy).streetname,
              (a.addy).streettypeabbrev,
              (a.addy).postdirabbrev,
              (a.addy).internal,
              (a.addy).location,
              (a.addy).stateabbrev,
              (a.addy).zip,
              a.rating
          ) as b
        ORDER BY b.rating LIMIT max_results
    LOOP

      ADDY := rec.addy;
      GEOMOUT := rec.geomout;
      RATING := rec.rating;

      RETURN NEXT;

      IF RATING = 0 THEN
        RETURN;
      END IF;

    END LOOP;

    IF RATING IS NOT NULL THEN
      RETURN;
    END IF;
  END IF;

  -- No zip code, try state/location, need both or we'll get too much stuffs.
  IF IN_ADDY.zip IS NOT NULL OR (IN_ADDY.stateAbbrev IS NOT NULL AND IN_ADDY.location IS NOT NULL) THEN
    FOR rec in SELECT * FROM tiger.geocode_location(IN_ADDY, restrict_geom) As b ORDER BY b.rating LIMIT max_results
    LOOP
      ADDY := rec.addy;
      GEOMOUT := rec.geomout;
      RATING := rec.rating;

      RETURN NEXT;
      IF RATING = 100 THEN
        RETURN;
      END IF;
    END LOOP;

  END IF;

  RETURN;

END;
$_$ LANGUAGE plpgsql
COST 1000
STABLE PARALLEL SAFE
ROWS 1;
 /***
 *
 * Copyright (C) 2011-2023 Regina Obe and Leo Hsu (Paragon Corporation)
 **/
-- This function given a point try to determine the approximate street address (norm_addy form)
-- and array of cross streets, as well as interpolated points along the streets
-- Use case example an address at the intersection of 3 streets: SELECT pprint_addy(r.addy[1]) As st1, pprint_addy(r.addy[2]) As st2, pprint_addy(r.addy[3]) As st3, array_to_string(r.street, ',') FROM reverse_geocode(ST_GeomFromText('POINT(-71.057811 42.358274)',4269)) As r;
--set search_path=tiger,public;

CREATE OR REPLACE FUNCTION reverse_geocode(IN pt geometry, IN include_strnum_range boolean DEFAULT false, OUT intpt geometry[], OUT addy norm_addy[], OUT street character varying[])
  RETURNS record AS
$BODY$
DECLARE
  var_redge RECORD;
  var_state text := NULL;
  var_stusps text := NULL;
  var_countyfp text := NULL;
  var_addy NORM_ADDY;
  var_addy_alt NORM_ADDY;
  var_nstrnum numeric(10);
  var_primary_line geometry := NULL;
  var_primary_dist numeric(10,2) ;
  var_pt geometry;
  var_place varchar;
  var_county varchar;
  var_stmt text;
  var_debug boolean =  get_geocode_setting('debug_reverse_geocode')::boolean;
  var_rating_highway integer = COALESCE(get_geocode_setting('reverse_geocode_numbered_roads')::integer,0);/**0 no preference, 1 prefer highway number, 2 prefer local name **/
  var_zip varchar := NULL;
  var_primary_fullname varchar := '';
BEGIN
	IF pt IS NULL THEN
		RETURN;
	ELSE
		IF ST_SRID(pt) = 4269 THEN
			var_pt := pt;
		ELSIF ST_SRID(pt) > 0 THEN
			var_pt := ST_Transform(pt, 4269);
		ELSE --If srid is unknown, assume its 4269
			var_pt := ST_SetSRID(pt, 4269);
		END IF;
		var_pt := ST_SnapToGrid(var_pt, 0.00005); /** Get rid of floating point junk that would prevent intersections **/
	END IF;
	-- Determine state tables to check
	-- this is needed to take advantage of constraint exclusion
	IF var_debug THEN
		RAISE NOTICE 'Get matching states start: %', clock_timestamp();
	END IF;
	SELECT statefp, stusps INTO var_state, var_stusps FROM state WHERE ST_Intersects(the_geom, var_pt) LIMIT 1;
	IF var_debug THEN
		RAISE NOTICE 'Get matching states end: % -  %', var_state, clock_timestamp();
	END IF;
	IF var_state IS NULL THEN
		-- We don't have any data for this state
		RETURN;
	END IF;
	IF var_debug THEN
		RAISE NOTICE 'Get matching counties start: %', clock_timestamp();
	END IF;
	-- locate county
	var_stmt := 'SELECT countyfp, name  FROM  county WHERE  statefp =  $1 AND ST_Intersects(the_geom, $2) LIMIT 1;';
	EXECUTE var_stmt INTO var_countyfp, var_county USING var_state, var_pt ;

	--locate zip
	var_stmt := 'SELECT zcta5ce  FROM zcta5 WHERE statefp = $1 AND ST_Intersects(the_geom, $2)  LIMIT 1;';
	EXECUTE var_stmt INTO var_zip USING var_state, var_pt;
	-- locate city
	IF var_zip > '' THEN
	      var_addy.zip := var_zip ;
	END IF;

	var_stmt := 'SELECT z.name  FROM place As z WHERE  z.statefp =  $1 AND ST_Intersects(the_geom, $2) LIMIT 1;';
	EXECUTE var_stmt INTO var_place USING var_state, var_pt ;
	IF var_place > '' THEN
			var_addy.location := var_place;
	ELSE
		var_stmt := 'SELECT z.name  FROM cousub As z WHERE  z.statefp =  $1 AND ST_Intersects(the_geom, $2) LIMIT 1;';
		EXECUTE var_stmt INTO var_place USING var_state, var_pt ;
		IF var_place > '' THEN
			var_addy.location := var_place;
		-- ELSIF var_zip > '' THEN
		-- 	SELECT z.city INTO var_place FROM zip_lookup_base As z WHERE  z.statefp =  var_state AND z.county = var_county AND z.zip = var_zip LIMIT 1;
		-- 	var_addy.location := var_place;
		END IF;
	END IF;

	IF var_debug THEN
		RAISE NOTICE 'Get matching counties end: % - %',var_countyfp,  clock_timestamp();
	END IF;
	IF var_countyfp IS NULL THEN
		-- We don't have any data for this county
		RETURN;
	END IF;

	var_addy.stateAbbrev = var_stusps;

	-- Find the street edges that this point is closest to with tolerance of 0.005 but only consider the edge if the point is contained in the right or left face
	-- Then order addresses by proximity to road
	IF var_debug THEN
		RAISE NOTICE 'Get matching edges start: %', clock_timestamp();
	END IF;

	var_stmt := '
	    WITH ref AS (
	        SELECT ' || quote_literal(var_pt::text) || '::geometry As ref_geom ) ,
			f AS
			( SELECT faces.* FROM faces  CROSS JOIN ref
			WHERE faces.statefp = ' || quote_literal(var_state) || ' AND faces.countyfp = ' || quote_literal(var_countyfp) || '
				AND ST_Intersects(faces.the_geom, ref_geom)
				    ),
			e AS
			( SELECT edges.tlid , edges.statefp, edges.the_geom, CASE WHEN edges.tfidr = f.tfid THEN ''R'' WHEN edges.tfidl = f.tfid THEN ''L'' ELSE NULL END::varchar As eside,
                    ST_ClosestPoint(edges.the_geom,ref_geom) As center_pt, ref_geom
				FROM edges INNER JOIN f ON (f.statefp = edges.statefp AND (edges.tfidr = f.tfid OR edges.tfidl = f.tfid))
				    CROSS JOIN ref
			WHERE edges.statefp = ' || quote_literal(var_state) || ' AND edges.countyfp = ' || quote_literal(var_countyfp) || '
				AND ST_DWithin(edges.the_geom, ref.ref_geom, 0.01) AND (edges.mtfcc LIKE ''S%'') --only consider streets and roads
				  )	,
			ea AS
			(SELECT e.statefp, e.tlid, a.fromhn, a.tohn, e.center_pt, ref_geom, a.zip, a.side, e.the_geom
				FROM e LEFT JOIN addr As a ON (a.statefp = ' || quote_literal(var_state) || '  AND e.tlid = a.tlid and e.eside = a.side)
				)
		SELECT *
		FROM (SELECT DISTINCT ON(tlid,side)  foo.fullname, foo.predirabrv, foo.streetname, foo.sufdirabrv, foo.streettypeabbrev, foo.zip,  foo.center_pt,
			  side, to_number(CASE WHEN trim(fromhn) ~ ''^[0-9]+$'' THEN fromhn ELSE NULL END,''99999999'')  As fromhn, to_number(CASE WHEN trim(tohn) ~ ''^[0-9]+$'' THEN tohn ELSE NULL END,''99999999'') As tohn,
			  ST_GeometryN(ST_Multi(line),1) As line, dist
		FROM
		  (SELECT e.tlid, e.the_geom As line, n.fullname, COALESCE(n.prequalabr || '' '','''')  || n.name AS streetname, n.predirabrv, COALESCE(suftypabrv, pretypabrv) As streettypeabbrev,
		      n.sufdirabrv, e.zip, e.side, e.fromhn, e.tohn , e.center_pt,
		          ST_DistanceSphere(ST_SetSRID(e.center_pt,4326),ST_SetSRID(ref_geom,4326)) As dist
				FROM ea AS e
					LEFT JOIN (SELECT featnames.* FROM featnames
			    WHERE featnames.statefp = ' || quote_literal(var_state) ||'   ) AS n ON (n.statefp =  e.statefp AND n.tlid = e.tlid)
				ORDER BY dist LIMIT 50 ) As foo
				ORDER BY foo.tlid, foo.side, ';

	    -- for numbered street/road use var_rating_highway to determine whether to prefer numbered or not (0 no pref, 1 prefer numbered, 2 prefer named)
		var_stmt := var_stmt || ' CASE $1 WHEN 0 THEN 0  WHEN 1 THEN CASE WHEN foo.fullname ~ ''[0-9]+'' THEN 0 ELSE 1 END ELSE CASE WHEN foo.fullname > '''' AND NOT (foo.fullname ~ ''[0-9]+'') THEN 0 ELSE 1 END END ';

		-- penalize ranges with no street name or no address range if there are others with addresses within 70 meters
		var_stmt := var_stmt || ',  foo.fullname ASC NULLS LAST, dist LIMIT 50) As f
		ORDER BY CASE WHEN f.dist < 70 THEN 0 ELSE f.dist END, CASE WHEN fullname > '''' THEN 0 ELSE 1 END,
			CASE WHEN f.fromhn IS NOT NULL THEN 0 ELSE 1 END, f.dist ';

	IF var_debug = true THEN
	    RAISE NOTICE 'Statement 1: %', replace(var_stmt, '$1', var_rating_highway::text);
	END IF;

    FOR var_redge IN EXECUTE var_stmt USING var_rating_highway LOOP
        IF var_debug THEN
            RAISE NOTICE 'Start Get matching edges loop: %,%', var_primary_line, clock_timestamp();
        END IF;
        IF var_primary_line IS NULL THEN --this is the first time in the loop and our primary guess
            var_primary_line := var_redge.line;
            var_primary_dist := var_redge.dist;
        END IF;

        IF var_redge.fullname IS NOT NULL AND COALESCE(var_primary_fullname,'') = '' THEN -- this is the first non-blank name we are hitting grab info
            var_primary_fullname := var_redge.fullname;
            var_addy.streetname = var_redge.streetname;
            var_addy.streettypeabbrev := var_redge.streettypeabbrev;
            var_addy.predirabbrev := var_redge.predirabrv;
			var_addy.postDirAbbrev := var_redge.sufdirabrv;
        END IF;

        IF ST_Intersects(var_redge.line, var_primary_line) THEN
            var_addy.streetname := var_redge.streetname;

            var_addy.streettypeabbrev := var_redge.streettypeabbrev;
            var_addy.address := var_nstrnum;
            IF  var_redge.fromhn IS NOT NULL THEN
                --interpolate the number -- note that if fromhn > tohn we will be subtracting which is what we want
                var_nstrnum := (var_redge.fromhn + ST_LineLocatePoint(var_redge.line, var_pt)*(var_redge.tohn - var_redge.fromhn))::numeric(10);
                -- The odd even street number side of street rule
                IF (var_nstrnum  % 2)  != (var_redge.tohn % 2) THEN
                    var_nstrnum := CASE WHEN var_nstrnum + 1 NOT BETWEEN var_redge.fromhn AND var_redge.tohn THEN var_nstrnum - 1 ELSE var_nstrnum + 1 END;
                END IF;
                var_addy.address := var_nstrnum;
            END IF;
            IF var_redge.zip > ''  THEN
                var_addy.zip := var_redge.zip;
            ELSE
                var_addy.zip := var_zip;
            END IF;
            -- IF var_redge.location > '' THEN
            --     var_addy.location := var_redge.location;
            -- ELSE
            --     var_addy.location := var_place;
            -- END IF;

            -- This is a cross streets - only add if not the primary address street
            IF var_redge.fullname > '' AND var_redge.fullname <> var_primary_fullname THEN
                street := array_append(street, (CASE WHEN include_strnum_range THEN COALESCE(var_redge.fromhn::varchar, '')::varchar || COALESCE(' - ' || var_redge.tohn::varchar,'')::varchar || ' '::varchar  ELSE '' END::varchar ||  COALESCE(var_redge.fullname::varchar,''))::varchar);
            END IF;

            -- consider this a potential address
            IF (var_redge.dist < var_primary_dist*1.1 OR var_redge.dist < 20)   THEN
                 -- We only consider this a possible address if it is really close to our point
                 intpt := array_append(intpt,var_redge.center_pt);
                -- note that ramps don't have names or addresses but they connect at the edge of a range
                -- so for ramps the address of connecting is still useful
                IF var_debug THEN
                    RAISE NOTICE 'Current addresses: %, last added, %, street: %, %', addy, var_addy, var_addy.streetname, clock_timestamp();
                END IF;
                 addy := array_append(addy, var_addy);

                -- Use current values streetname for previous value if previous value has no streetname
				IF var_addy.streetname > '' AND array_upper(addy,1) > 1 AND COALESCE(addy[array_upper(addy,1) - 1].streetname, '') = ''  THEN
					-- the match is probably an offshoot of some sort
					-- replace prior entry with streetname of new if prior had no streetname
					var_addy_alt := addy[array_upper(addy,1)- 1];
					IF var_debug THEN
						RAISE NOTICE 'Replacing answer : %, %', addy[array_upper(addy,1) - 1], clock_timestamp();
					END IF;
					var_addy_alt.streetname := var_addy.streetname;
					var_addy_alt.streettypeabbrev := var_addy.streettypeabbrev;
                    var_addy_alt.predirabbrev := var_addy.predirabbrev;
					var_addy_alt.postDirAbbrev := var_addy.postDirAbbrev;
					addy[array_upper(addy,1) - 1 ] := var_addy_alt;
					IF var_debug THEN
						RAISE NOTICE 'Replaced with : %, %', var_addy_alt, clock_timestamp();
					END IF;
				END IF;

				IF var_debug THEN
					RAISE NOTICE 'End Get matching edges loop: %', clock_timestamp();
					RAISE NOTICE 'Final addresses: %, %', addy, clock_timestamp();
				END IF;

            END IF;
        END IF;

    END LOOP;

    -- not matching roads or streets, just return basic info
    IF NOT FOUND THEN
        addy := array_append(addy,var_addy);
        IF var_debug THEN
            RAISE NOTICE 'No address found: adding: % street: %, %', var_addy, var_addy.streetname, clock_timestamp();
        END IF;
    END IF;
    IF var_debug THEN
        RAISE NOTICE 'current array count : %, %', array_upper(addy,1), clock_timestamp();
    END IF;

    RETURN;
END;
$BODY$
  LANGUAGE plpgsql STABLE
  COST 1000;
 /***
 *
 * Copyright (C) 2012 Regina Obe and Leo Hsu (Paragon Corporation)
 **/
-- This function given a geometry try will try to determine the tract.
-- It defaults to returning the tract name but can be changed to return track geoid id.
-- pass in 'tract_id' to get the full geoid, 'name' to get the short decimal name

CREATE OR REPLACE FUNCTION get_tract(IN loc_geom geometry, output_field text DEFAULT 'name')
  RETURNS text AS
$$
DECLARE
  var_state text := NULL;
  var_stusps text := NULL;
  var_result text := NULL;
  var_loc_geom geometry;
  var_stmt text;
  var_debug boolean = false;
BEGIN
	IF loc_geom IS NULL THEN
		RETURN null;
	ELSE
		IF ST_SRID(loc_geom) = 4269 THEN
			var_loc_geom := loc_geom;
		ELSIF ST_SRID(loc_geom) > 0 THEN
			var_loc_geom := ST_Transform(loc_geom, 4269);
		ELSE --If srid is unknown, assume its 4269
			var_loc_geom := ST_SetSRID(loc_geom, 4269);
		END IF;
		IF GeometryType(var_loc_geom) != 'POINT' THEN
			var_loc_geom := ST_Centroid(var_loc_geom);
		END IF;
	END IF;
	-- Determine state tables to check
	-- this is needed to take advantage of constraint exclusion
	IF var_debug THEN
		RAISE NOTICE 'Get matching states start: %', clock_timestamp();
	END IF;
	SELECT statefp, stusps INTO var_state, var_stusps FROM state WHERE ST_Intersects(the_geom, var_loc_geom) LIMIT 1;
	IF var_debug THEN
		RAISE NOTICE 'Get matching states end: % -  %', var_state, clock_timestamp();
	END IF;
	IF var_state IS NULL THEN
		-- We don't have any data for this state
		RAISE NOTICE 'No data for this state';
		RETURN NULL;
	END IF;
	-- locate county
	var_stmt := 'SELECT ' || quote_ident(output_field) || ' FROM tract WHERE statefp =  $1 AND ST_Intersects(the_geom, $2) LIMIT 1;';
	EXECUTE var_stmt INTO var_result USING var_state, var_loc_geom ;
	RETURN var_result;
END;
$$
  LANGUAGE plpgsql IMMUTABLE
  COST 500;
SELECT pg_catalog.pg_extension_config_dump('geocode_settings', '');
SELECT pg_catalog.pg_extension_config_dump('pagc_gaz', 'WHERE is_custom=true');
SELECT pg_catalog.pg_extension_config_dump('pagc_lex', 'WHERE is_custom=true');
SELECT pg_catalog.pg_extension_config_dump('pagc_rules', 'WHERE is_custom=true');
SELECT postgis_extension_drop_if_exists('postgis_tiger_geocoder', 'DROP SCHEMA tiger_data');
-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
--
----
-- PostGIS - Spatial Types for PostgreSQL
-- http://postgis.net
--
-- Copyright (C) 2011 Regina Obe <lr@pcorp.us>
--
-- This is free software; you can redistribute and/or modify it under
-- the terms of the GNU General Public Licence. See the COPYING file.
--
-- Author: Regina Obe <lr@pcorp.us>
--
-- This drops extension helper functions
-- and should be called at the end of the extension upgrade file
DROP FUNCTION postgis_extension_remove_objects(text, text);
DROP FUNCTION postgis_extension_drop_if_exists(text, text);
DROP FUNCTION IF EXISTS postgis_extension_AddToSearchPath(varchar);
DROP FUNCTION IF EXISTS postgis_extension_AddToSearchPath(text);
