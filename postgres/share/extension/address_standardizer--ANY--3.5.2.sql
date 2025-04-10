---------------------------------------------------------------------
-- Core function to access the PAGC address standardizer
-- Author: Stephen Woodbridge <woodbri@imaptools.com>
---------------------------------------------------------------------

-- Availability: 3.4.0
CREATE OR REPLACE FUNCTION debug_standardize_address(
        lextab text,
        gaztab text,
        rultab text,
        micro text,
        macro text DEFAULT NULL )
    RETURNS text
    AS  '$libdir/address_standardizer-3', 'debug_standardize_address'
    LANGUAGE 'c' IMMUTABLE COST 200;

CREATE OR REPLACE FUNCTION standardize_address(
        lextab text,
        gaztab text,
        rultab text,
        micro text,
        macro text )
    RETURNS stdaddr
    AS  '$libdir/address_standardizer-3', 'standardize_address'
    LANGUAGE 'c' IMMUTABLE STRICT COST 200;

CREATE OR REPLACE FUNCTION standardize_address(
        lextab text,
        gaztab text,
        rultab text,
        address text )
    RETURNS stdaddr
    AS  '$libdir/address_standardizer-3', 'standardize_address1'
    LANGUAGE 'c' IMMUTABLE STRICT COST 200;

CREATE OR REPLACE FUNCTION parse_address(IN text,
        OUT num text,
        OUT street text,
        OUT street2 text,
        OUT address1 text,
        OUT city text,
        OUT state text,
        OUT zip text,
        OUT zipplus text,
        OUT country text)
    RETURNS record
    AS  '$libdir/address_standardizer-3', 'parse_address'
    LANGUAGE 'c' IMMUTABLE STRICT;


