# this makefile is based on the PGXN template
EXTVERSION   = $(shell grep -m 1 '[[:space:]]\{8\}"version":' META.json | \
               sed -e 's/[[:space:]]*"version":[[:space:]]*"\([^"]*\)",\{0,1\}/\1/')
DISTVERSION  = $(shell grep -m 1 '[[:space:]]\{3\}"version":' META.json | \
               sed -e 's/[[:space:]]*"version":[[:space:]]*"\([^"]*\)",\{0,1\}/\1/')
EXTABSTRACT  = $(shell grep -m 1 '[[:space:]]\{8\}"abstract":' META.json | \
               sed -e 's/[[:space:]]*"abstract":[[:space:]]*"\([^"]*\)",\{0,1\}/\1/')


EXTENSION    = dsef
DATA 		    = $(wildcard sql/*--*.sql)
TESTS        = $(wildcard test/sql/*.sql)
REGRESS      = $(patsubst test/sql/%.sql,%,$(TESTS))
REGRESS_OPTS = --inputdir=test
PG_CONFIG   ?= pg_config
EXTRA_CLEAN = sql/dsef--$(EXTVERSION).sql tle/dsef.tle

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

all: sql/dsef--$(EXTVERSION).sql tle/dsef.tle

sql/dsef--$(EXTVERSION).sql: sql/dsef.sql
	cp $< $@

tle/dsef.tle: sql/dsef.sql
	echo " DROP EXTENSION IF EXISTS dsef; " >$@
	echo " SELECT * FROM pgtle.uninstall_extension_if_exists('dsef'); " >>$@
	echo " SELECT pgtle.install_extension('dsef','$(EXTVERSION)','$(EXTABSTRACT)',\$$_pgtle_\$$ " >>$@
	cat sql/dsef.sql >>$@
	echo " \$$_pgtle_\$$); " >>$@
	echo " CREATE EXTENSION dsef; " >>$@

dist:
	git archive --format zip --prefix=dsef-$(DISTVERSION)/ -o dsef-$(DISTVERSION).zip HEAD
