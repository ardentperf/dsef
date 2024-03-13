DiffStats and ExplainFull (DSEF)
=================================

*Detailed SQL reports for 3rd party help & support*

.

DiffStats and ExplainFull can generate detailed reports which are useful for 
troubleshooting performance of a SQL statement, and especially for working 
with 3rd parties who are helping in the process. It reduces the amount of 
back-and-forth requests for information by capturing a great deal of commonly 
useful data about the performance of a SQL statement.

The extension consists of a number of functions which are installed into the 
database. These functions fall into two broad categories:

1. A function that is a wrapper around "EXPLAIN ANALYZE" - besides ensuring 
   that all diagnostics options are used, it also dumps additional information
   like server version and full planner statistics for all functions and tables 
   referenced by the SQL.
2. A set of functions to capture and report all possible statistics tracked by 
   the database during a test SQL statement execution


Installation
-------------

The quickest way to install DSEF is to create its functions with this command:

    curl -O https://raw.githubusercontent.com/ardentperf/dsef/main/sql/dsef.sql
    psql <dsef.sql

The SQL file at the URL above can also be opened and executed with a GUI development 
tool like pgAdmin.

Alternatively, DSEF can be installed by an administrator as an **extension**. This 
requires a few more steps but has some advantages. The functions are clearly identified 
as part of a single package, the functions are not mixed up with user code in pg_dump
backups, and the package versioning and metadata is tracked in system catalogs and
much easier to manage. Installation as an extension is preferred, when possible.

Install extension to self-managed PostgreSQL from source:

    git clone https://github.com/ardentperf/dsef
    
    make
    make installcheck
    make install

Install extension to self-managed PostgreSQL with PGXN

    apt install pgxnclient

    pgxn install dsef

Install extension to RDS 14.5+ (including Aurora)

    aws rds modify-db-parameter-group
       --db-parameter-group-name custom-param-group-name
       --parameters "ParameterName=shared_preload_libraries,ParameterValue=pg_tle"    
    CREATE EXTENSION pg_tle;

    curl -O https://raw.githubusercontent.com/ardentperf/dsef/main/tle/dsef.tle
    psql <dsef.tle


Un-Installation
----------------

If DSEF is installed as an extension, then uninstalling it is very simple:

    DROP EXTENSION dsef

If DSEF was installed as functions, you can carefully copy-and-paste the `DROP FUNCTION` 
commands from https://github.com/ardentperf/dsef/blob/main/sql/uninstall_dsef.sql


Dependencies
-------------

To use the "ExplainFull" functionality, the only required privilege is the 
ability to create a function.

At present, the "DiffStats" functionality requires privileges to create a temporary 
table to pass information to subsequent function calls. (Core PostgreSQL does not 
yet provide session-level variables.) As a result, the "DiffStats" functionality will 
not work on a hot standby or otherwise read-only PostgreSQL system.

Optional dependencies:
* If pg_proctab is available, DSEF will use it to include all available 
  Operating System statistics in its report.
* On Aurora, DSEF will include wait event statistics at both the system and 
  session level in its report.
* With appropriate privileges, DSEF can be installed as an extension on 
  self-hosted PostgreSQL and on RDS PosgreSQL 14.5+


A Few Simple Examples (Tutorial)
---------------------------------

First step: use the `explain_analyze_full()` function instead of "explain analyze". It 
will run EXPLAIN ANALYZE under the covers and will ensure that the full output is always 
printed. This is especially helpful when working with other people on understanding a 
query, because it reduces the number of times people need to ask for more information.

    select * from explain_analyze_full('select * from sbtest1 limit 1');

PostgreSQL has a special kind of quoting called "dollar quoting" which is very useful 
if we need to use single-quotes in our query text.

    select * from explain_analyze_full($$ select sum(k) from sbtest1 where c>'97string0' $$); 

To get even more information (including wait times on Aurora), we wrap our explain analyze 
inside `ds_start()` and `ds_report()`. This will take a snapshot of system counters and 
produce a report about which counters changed during query execution. Note that as of 2024, 
most open source PostgreSQL counters operate at the database level rather than the session 
level. These can be very useful on a test system that's otherwise idle, besides the debug 
session running this command. On a busier system, it can still be helpful to have an idea
what the overall system profile is during execution. Aurora wait events are captured and 
reported at both the system and the session level.

There is sometimes a short delay in PostgreSQL after query completion and before stat updates 
become visible, so it helps to include a small `pg_sleep()` before getting the report if 
you are copy/pasting everything at once rather than keying by hand.

NOTE: the `ds_start()` function will attempt to automatically install and use the 
`pg_proctab` extension, if it is available and the user has privileges. If this causes an 
error, then the error is ignored and `pg_proctab` statistics are not included in the report.

    select ds_start();

      select * from explain_analyze_full('select * from customers c,customers2 c2  where c.id=c2.id limit 1000000');

    select pg_sleep(0.05); select * from ds_report();

More than 10 years ago, Tom Kyte published a short snippet of code called RunStats. Simple 
yet brilliant - it allowed a SQL statement to be executed twice, compared stats between the 
two executions, and printed a report. We can do the same thing on PostgreSQL by inserting 
a call to `ds_capture()` between our two SQL statements.

    select ds_start(); 

      select * from explain_analyze_full($$ select * from customers c,customers2 c2  where c.id=c2.id limit 1000 $$); 

    select * from ds_capture(); 

      set enable_indexscan=off; 
      select * from explain_analyze_full($$ select * from customers c,customers2 c2  where c.id=c2.id limit 1000 $$); 

    select pg_sleep(0.05); select * from ds_report_diff();

In PostgreSQL, we need to be careful about running DML inside of EXPLAIN ANALYZE because 
the SQL is actually executed to gather stats. This means that we typically want to wrap the 
command inside a transaction, and then ROLLBACK.

    select ds_start(); 

      BEGIN; 
      select * from explain_analyze_full($$ update my_test set t=99 where i=100000 $$); 
      ROLLBACK; 

    select pg_sleep(0.05); select * from ds_report();


