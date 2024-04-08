-- most extensions will complain if script is sourced in psql, rather than via CREATE EXTENSION
--
-- DSEF allows the option of installation via SQL

CREATE OR REPLACE FUNCTION ds_version() RETURNS text AS $$
  -- the version of this package
  SELECT 'DSEF for PostgreSQL (DiffStats & ExplainFull) Version: 2024.4.8';
$$ LANGUAGE SQL;



CREATE OR REPLACE FUNCTION ds_set(p_setting text) RETURNS int AS $$
DECLARE
  v_error text;
BEGIN 
  EXECUTE 'SET '||p_setting;
  RETURN NULL;
EXCEPTION 
  WHEN OTHERS THEN 
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    RAISE NOTICE 'WARNING: SET %: %',p_setting,v_error;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION explain_analyze_full(p_sql text,p_format text DEFAULT 'TEXT',p_verbose boolean DEFAULT false) RETURNS TABLE ("QUERY PLAN" text) AS $$
DECLARE
  v_server_version_num numeric = current_setting('server_version_num');
  -- the following extracts the YugabyteDB version. Will be empty string for PostgreSQL so the test >'n.nn' will not apply
  v_yugabytedb_version     text    =  regexp_replace(current_setting('server_version'),'([0-9.]+)(-YB-([0-9.]+)-)?.*','\3');
  v_query text;
  v_function_count numeric;
  v_tab record;
  v_col record;
  v_all_settings_to_output text[] = array[
       'log_temp_files'
      ,'log_lock_waits'
      ,'deadlock_timeout'
      ,'track_functions'
      ,'track_counts'
      ,'log_parser_stats'
      ,'log_planner_stats'
      ,'log_executor_stats'
      ,'debug_print_parse'
      ,'debug_print_rewritten'
      ,'debug_print_plan'
      ,'debug_pretty_print'
      ,'track_io_timing'
      ,'track_wal_io_timing'
      ,'log_min_messages'
      ,'default_statistics_target'
    ];
  v_guc_explain_settings text[] = array[
       'enable_seqscan'
      ,'enable_indexscan'
      ,'enable_indexonlyscan'
      ,'enable_bitmapscan'
      ,'enable_tidscan'
      ,'enable_sort'
      ,'enable_hashagg'
      ,'enable_material'
      ,'enable_nestloop'
      ,'enable_mergejoin'
      ,'enable_hashjoin'
      ,'enable_gathermerge'
      ,'enable_partitionwise_join'
      ,'enable_partitionwise_aggregate'
      ,'enable_parallel_append'
      ,'enable_parallel_hash'
      ,'enable_partition_pruning'
      ,'geqo'
      ,'optimize_bounded_sort'
      ,'parallel_leader_participation'
      ,'jit'
      ,'from_collapse_limit'
      ,'join_collapse_limit'
      ,'geqo_threshold'
      ,'geqo_effort'
      ,'geqo_pool_size'
      ,'geqo_generations'
      ,'temp_buffers'
      ,'work_mem'
      ,'effective_io_concurrency'
      ,'max_parallel_workers_per_gather'
      ,'max_parallel_workers'
      ,'effective_cache_size'
      ,'min_parallel_table_scan_size'
      ,'min_parallel_index_scan_size'
      ,'seq_page_cost'
      ,'random_page_cost'
      ,'cpu_tuple_cost'
      ,'cpu_index_tuple_cost'
      ,'cpu_operator_cost'
      ,'parallel_tuple_cost'
      ,'parallel_setup_cost'
      ,'jit_above_cost'
      ,'jit_optimize_above_cost'
      ,'jit_inline_above_cost'
      ,'cursor_tuple_fraction'
      ,'geqo_selection_bias'
      ,'geqo_seed'
      ,'search_path'
      ,'constraint_exclusion'
      ,'force_parallel_mode'
      ,'plan_cache_mode'
    ]; -- all GUC_EXPLAIN settings from guc.c in v12 when it was added; included in this report for v11 and older
BEGIN
  RETURN QUERY SELECT '__________ '||ds_version()||' __________';
  RETURN QUERY SELECT 'clock_timestamp: '||clock_timestamp();
  RETURN QUERY SELECT 'pg_version: '||version();
  BEGIN
    RETURN QUERY SELECT 'aurora_version: '||aurora_version();
  EXCEPTION WHEN undefined_function THEN NULL;
  END;
  RETURN QUERY SELECT ' ';

  -- these are all valid on 9.0+ per docs
  PERFORM ds_set($p$ log_min_messages=panic     $p$);
  PERFORM ds_set($p$ log_temp_files=0           $p$);
  PERFORM ds_set($p$ deadlock_timeout='1ms'     $p$);
  PERFORM ds_set($p$ log_lock_waits=on          $p$);
  PERFORM ds_set($p$ track_functions='all'      $p$);
  PERFORM ds_set($p$ track_counts=on;           $p$);
  IF p_verbose THEN
    PERFORM ds_set($p$ log_parser_stats=on        $p$);
    PERFORM ds_set($p$ log_planner_stats=on       $p$);
    PERFORM ds_set($p$ log_executor_stats=on      $p$);
    PERFORM ds_set($p$ debug_print_parse=on       $p$);
    PERFORM ds_set($p$ debug_print_rewritten=on   $p$);
    PERFORM ds_set($p$ debug_print_plan=on        $p$);
    PERFORM ds_set($p$ debug_pretty_print=off     $p$);
  END IF;

  v_query:='EXPLAIN (ANALYZE,VERBOSE,COSTS,BUFFERS,FORMAT '||p_format;
  IF v_server_version_num>=90200 THEN
    v_query = v_query||',TIMING';
    PERFORM ds_set($p$ track_io_timing=on       $p$);
  END IF;
  IF v_server_version_num>=120000 THEN
    v_query = v_query||',SETTINGS';
    IF NOT p_verbose THEN
      v_guc_explain_settings = array[]::text[];
    END IF;
  END IF;
  IF v_server_version_num>=130000 THEN
    v_query = v_query||',WAL';
  END IF;
  IF v_server_version_num>=140000 THEN
    PERFORM ds_set($p$ track_wal_io_timing=on   $p$);
  END IF;
  IF v_yugabytedb_version>='2.18' THEN
    v_query = v_query||',DIST';
  END IF;
  IF v_yugabytedb_version>='2.19' THEN
    v_query = v_query||',DEBUG';
  END IF;

  v_query:=v_query||') '||p_sql;
  RAISE NOTICE 'INFO: %',v_query;
  RETURN QUERY SELECT v_query;
  RETURN QUERY SELECT ' ';

  SET client_min_messages=debug5;
  RETURN QUERY EXECUTE v_query;
  RAISE NOTICE 'INFO: query execution complete; now resetting client_min_messages';
  RESET client_min_messages;

  SELECT COUNT(*) FROM pg_stat_xact_user_functions WHERE calls>0 AND funcname<>'ds_set' INTO v_function_count;
  IF v_function_count>0 THEN
    RETURN QUERY SELECT ' ' UNION ALL SELECT ' ' UNION ALL SELECT ' ';
    RETURN QUERY SELECT 'Cost      | Rows      | SpprtFn | Kind | SecDef | Leakprf | Strct | RetSet | Vltl | Prll | Calls     | Language | Function Name [Config]';
    RETURN QUERY SELECT '----------+-----------+---------+------+--------+---------+-------+--------+------+------+-----------+----------+------------------------';
    IF v_server_version_num<90600 THEN
      RETURN QUERY SELECT
          LPAD(procost::text,9)||' | '||
          LPAD(prorows::text,9)||' | '||
          CASE WHEN protransform=0::oid THEN 'No      | ' ELSE 'Yes     | ' END||
          CASE WHEN proisagg THEN '   a | ' ELSE '   f | ' END||
          CASE WHEN prosecdef THEN 'Yes    | ' ELSE 'No     | ' END||
          CASE WHEN proleakproof THEN 'Yes     | ' ELSE 'No      | ' END||
          CASE WHEN proisstrict THEN 'Yes   | ' ELSE 'No    | ' END||
          CASE WHEN proretset THEN 'Yes    | ' ELSE 'No     | ' END||
          RPAD(provolatile,4)||' | '||
          '     | '||
          LPAD(calls::text,9)||' | '||
          RPAD(lanname,8)||' | '||
          schemaname||'.'||funcname||
          CASE WHEN proconfig IS NOT NULL THEN ' ['||array_to_string(proconfig,',')||']' ELSE '' END
        FROM pg_proc p, pg_stat_xact_user_functions f, pg_language l
        WHERE p.oid=f.funcid AND p.prolang=l.oid AND funcname<>'ds_set' AND f.calls>0;

    ELSE
      IF v_server_version_num<110000 THEN
        RETURN QUERY SELECT
            LPAD(procost::text,9)||' | '||
            LPAD(prorows::text,9)||' | '||
            CASE WHEN protransform=0::oid THEN 'No      | ' ELSE 'Yes     | ' END||
            CASE WHEN proisagg THEN '   a | ' ELSE '   f | ' END||
            CASE WHEN prosecdef THEN 'Yes    | ' ELSE 'No     | ' END||
            CASE WHEN proleakproof THEN 'Yes     | ' ELSE 'No      | ' END||
            CASE WHEN proisstrict THEN 'Yes   | ' ELSE 'No    | ' END||
            CASE WHEN proretset THEN 'Yes    | ' ELSE 'No     | ' END||
            RPAD(provolatile,4)||' | '||
            RPAD(proparallel,4)||' | '||
            LPAD(calls::text,9)||' | '||
            RPAD(lanname,8)||' | '||
            schemaname||'.'||funcname||
            CASE WHEN proconfig IS NOT NULL THEN ' ['||array_to_string(proconfig,',')||']' ELSE '' END
          FROM pg_proc p, pg_stat_xact_user_functions f, pg_language l
          WHERE p.oid=f.funcid AND p.prolang=l.oid AND funcname<>'ds_set' AND f.calls>0;

      ELSE
        IF v_server_version_num<120000 THEN
          RETURN QUERY SELECT
              LPAD(procost::text,9)||' | '||
              LPAD(prorows::text,9)||' | '||
              CASE WHEN protransform=0::oid THEN 'No      | ' ELSE 'Yes     | ' END||
              RPAD(prokind,4)||' | '||
              CASE WHEN prosecdef THEN 'Yes    | ' ELSE 'No     | ' END||
              CASE WHEN proleakproof THEN 'Yes     | ' ELSE 'No      | ' END||
              CASE WHEN proisstrict THEN 'Yes   | ' ELSE 'No    | ' END||
              CASE WHEN proretset THEN 'Yes    | ' ELSE 'No     | ' END||
              RPAD(provolatile,4)||' | '||
              RPAD(proparallel,4)||' | '||
              LPAD(calls::text,9)||' | '||
              RPAD(lanname,8)||' | '||
              schemaname||'.'||funcname||
              CASE WHEN proconfig IS NOT NULL THEN ' ['||array_to_string(proconfig,',')||']' ELSE '' END
            FROM pg_proc p, pg_stat_xact_user_functions f, pg_language l
            WHERE p.oid=f.funcid AND p.prolang=l.oid AND funcname<>'ds_set' AND f.calls>0;

        ELSE
          -- v12+
          RETURN QUERY SELECT
              LPAD(procost::text,9)||' | '||
              LPAD(prorows::text,9)||' | '||
              CASE WHEN prosupport=0::oid THEN 'No      | ' ELSE 'Yes     | ' END||
              RPAD(prokind,4)||' | '||
              CASE WHEN prosecdef THEN 'Yes    | ' ELSE 'No     | ' END||
              CASE WHEN proleakproof THEN 'Yes     | ' ELSE 'No      | ' END||
              CASE WHEN proisstrict THEN 'Yes   | ' ELSE 'No    | ' END||
              CASE WHEN proretset THEN 'Yes    | ' ELSE 'No     | ' END||
              RPAD(provolatile,4)||' | '||
              RPAD(proparallel,4)||' | '||
              LPAD(calls::text,9)||' | '||
              RPAD(lanname,8)||' | '||
              schemaname||'.'||funcname||
              CASE WHEN proconfig IS NOT NULL THEN ' ['||array_to_string(proconfig,',')||']' ELSE '' END
            FROM pg_proc p, pg_stat_xact_user_functions f, pg_language l
            WHERE p.oid=f.funcid AND p.prolang=l.oid AND funcname<>'ds_set' AND f.calls>0;

        END IF;
      END IF;
    END IF;
  END IF;
  
  RETURN QUERY SELECT ' ' UNION ALL SELECT ' ' UNION ALL SELECT ' ';

  FOR v_tab IN SELECT relid,schemaname,relname FROM pg_stat_xact_user_tables WHERE coalesce(seq_scan,0)+coalesce(idx_scan,0)>0 LOOP
    RETURN QUERY SELECT 'Table '||relnamespace::regnamespace::text||'.'||relname||': pages '||relpages||
          ', tuples '||reltuples||', allvisible '||relallvisible||', kind '||relkind::text 
      FROM pg_class WHERE oid=v_tab.relid;
    FOR v_col IN SELECT a.attname, a.atttypid, a.atttypmod, a.attstattarget, attnotnull,
                        null_frac, avg_width, n_distinct, correlation, histogram_bounds, most_common_vals, most_common_freqs
                 FROM pg_attribute a LEFT JOIN pg_stats s ON (a.attname=s.attname)
                 WHERE a.attrelid=v_tab.relid AND s.schemaname=v_tab.schemaname AND s.tablename=v_tab.relname LOOP
      RETURN QUERY SELECT '    '||v_col.attname||' '||pg_catalog.format_type(v_col.atttypid, v_col.atttypmod)||': stattarget '||v_col.attstattarget||
            ', notnull '||v_col.attnotnull||', null_frac '||coalesce(v_col.null_frac::text,'NULL')||
            ', avg_width '||coalesce(v_col.avg_width::text,'NULL')||', n_dist '||coalesce(v_col.n_distinct::text,'NULL')||
            ', corr '||coalesce(v_col.correlation::text,'NULL')||
            ', hist['||coalesce(array_length(v_col.histogram_bounds,1)::text,'')||'] '||
                       coalesce(left(v_col.histogram_bounds::text,24)||'...'||right(v_col.histogram_bounds::text,24),'NULL');
      RETURN QUERY SELECT '      mcv '||coalesce(left(v_col.most_common_vals::text,24)||'...'||right(v_col.most_common_vals::text,24),'NULL')||
            ', mcf '||coalesce(left(v_col.most_common_freqs::text,24)||'...'||right(v_col.most_common_freqs::text,24),'NULL')
        WHERE v_col.most_common_vals IS NOT NULL or v_col.most_common_freqs IS NOT NULL;
    END LOOP;

    IF v_server_version_num>=120000 THEN  -- v12 adds extended statistics
      RETURN QUERY SELECT '  Extended '||statistics_name||' '||attnames::text||': kinds '||kinds::text||
            ', n_distinct '||coalesce(n_distinct::text,'NULL')||
            ', mcf '||coalesce(left(most_common_freqs::text,24)||'...'||right(most_common_freqs::text,24),'NULL')||
            ', mcbf '||coalesce(left(most_common_base_freqs::text,24)||'...'||right(most_common_base_freqs::text,24),'NULL')
        FROM pg_stats_ext
        WHERE schemaname=v_tab.schemaname AND tablename=v_tab.relname;
    END IF;

    IF v_server_version_num>=150000 THEN  -- v15 adds indnullsnotdistinct
      RETURN QUERY SELECT '  Index '||c.relname||split_part(pg_get_indexdef(i.indexrelid,0,true),'USING',2)||
          ': pages '||relpages||', tuples '||reltuples||
          ', nkeyatts '||indnkeyatts||', isunique '||indisunique||', nullsnotdist '||indnullsnotdistinct||
          ', isclustered '||indisclustered||', isvalid '||indisvalid
        FROM pg_index i, pg_class c
        WHERE c.oid=i.indexrelid AND i.indrelid=v_tab.relid;

    ELSE  -- v14 and older
      RETURN QUERY SELECT '  Index '||c.relname||split_part(pg_get_indexdef(i.indexrelid,0,true),'USING',2)||
          ': pages '||relpages||', tuples '||reltuples||
          ', nkeyatts '||indnkeyatts||', isunique '||indisunique||
          ', isclustered '||indisclustered||', isvalid '||indisvalid
        FROM pg_index i, pg_class c
        WHERE c.oid=i.indexrelid AND i.indrelid=v_tab.relid;
    END IF;
  END LOOP;

  RETURN QUERY SELECT ' ' UNION ALL SELECT ' ' UNION ALL SELECT ' ';

  RETURN QUERY SELECT * FROM (SELECT
      RPAD('name',MAX(GREATEST(LENGTH(s.name),LENGTH('name'))) OVER ())||' | '||
      RPAD('setting',MAX(GREATEST(LENGTH(s.setting),LENGTH('setting'))) OVER ())||' | '||
      RPAD('unit',MAX(GREATEST(LENGTH(s.unit),LENGTH('unit'))) OVER ())||' | '||
      'source'
    FROM pg_settings s WHERE s.name=ANY(v_all_settings_to_output||v_guc_explain_settings)) subquery LIMIT 1;
  RETURN QUERY SELECT * FROM (SELECT
      RPAD('-',MAX(GREATEST(LENGTH(s.name),LENGTH('name'))) OVER (),'-')||'-+-'||
      RPAD('-',MAX(GREATEST(LENGTH(s.setting),LENGTH('setting'))) OVER (),'-')||'-+-'||
      RPAD('-',MAX(GREATEST(LENGTH(s.unit),LENGTH('name'))) OVER (),'-')||'-+-'||
      RPAD('-',MAX(GREATEST(LENGTH(s.source),LENGTH('source'))) OVER (),'-')
    FROM pg_settings s WHERE s.name=ANY(v_all_settings_to_output||v_guc_explain_settings)) subquery LIMIT 1;
  RETURN QUERY SELECT 
      RPAD(s.name,MAX(GREATEST(LENGTH(s.name),LENGTH('name'))) OVER ())||' | '||
      RPAD(s.setting,MAX(GREATEST(LENGTH(s.setting),LENGTH('setting'))) OVER ())||' | '||
      RPAD(COALESCE(s.unit,''),MAX(GREATEST(LENGTH(s.unit),LENGTH('unit'))) OVER ())||' | '||
      s.source
    FROM pg_settings s WHERE s.name=ANY(v_all_settings_to_output||v_guc_explain_settings);

  RETURN QUERY SELECT ' ' UNION ALL SELECT ' ' UNION ALL SELECT ' ';

  RETURN QUERY 
    WITH RECURSIVE all_roles AS (
      SELECT null::oid granted_to, oid FROM pg_roles WHERE rolname = current_user
      UNION ALL
      SELECT all_roles.oid, m.roleid FROM all_roles JOIN pg_auth_members m ON m.member = all_roles.oid
    )
    SELECT 
      CASE WHEN GRANTED_TO IS NULL THEN 'CURRENT_USER = ' ELSE '  ' END||a.oid::regrole::text||
      ' ('||CASE WHEN NOT r.rolsuper THEN 'not' ELSE 'IS' END||' superuser, '||
      CASE WHEN r.rolbypassrls THEN 'DOES' ELSE 'does not' END||' bypass RLS)'||
      CASE WHEN r.rolconfig IS NOT NULL THEN ' ['||array_to_string(r.rolconfig,',')||']' ELSE '' END||
      CASE WHEN GRANTED_TO IS NOT NULL THEN ' is granted to '||granted_to::regrole::text ELSE '' END
    FROM all_roles a, pg_roles r WHERE a.oid=r.oid;

  RESET ALL;
END;
$$ LANGUAGE plpgsql;






CREATE OR REPLACE FUNCTION ds_insert(p_run int) RETURNS int AS $$
DECLARE
  v_server_version_num numeric = current_setting('server_version_num');
BEGIN
  PERFORM pg_stat_clear_snapshot();

  -- PostgreSQL transaction-level statistics (9.1+ per docs)
  WITH x AS (SELECT COALESCE(c.relnamespace::regnamespace::text,s.schemaname) coalesce_schemaname,s.* FROM pg_stat_xact_all_tables s LEFT JOIN pg_class c ON (s.relid=c.reltoastrelid))
      ,f AS (SELECT * FROM pg_stat_xact_user_functions)
  INSERT INTO ds_tmpDiffStats
    SELECT p_run,statement_timestamp(),'10 Transaction','Stat:'||stat_name, units, coalesce(events,0), cum_time_ms FROM (
      SELECT coalesce_schemaname||':'||relname||':seq_scan' stat_name,'scans' units,seq_scan::numeric events,NULL::numeric cum_time_ms FROM x
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':seq_tup_read','tuples',seq_tup_read,NULL FROM x
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':idx_scan','scans',idx_scan,NULL FROM x
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':idx_tup_fetch','tuples',idx_tup_fetch,NULL FROM x
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':n_tup_ins','tuples',n_tup_ins,NULL FROM x
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':n_tup_upd','tuples',n_tup_upd,NULL FROM x
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':n_tup_del','tuples',n_tup_del,NULL FROM x
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':n_tup_hot_upd','tuples',n_tup_hot_upd,NULL FROM x
        UNION ALL
      SELECT schemaname||'.'||funcname||':total_time:calls','exec',calls,total_time FROM f
        UNION ALL
      SELECT schemaname||'.'||funcname||':self_time:calls','exec',calls,self_time FROM f
    ) q;

  -- PostgreSQL 9.2+ statistics
  WITH d AS (SELECT * FROM pg_stat_database WHERE datname=current_database())
      ,t AS (SELECT COALESCE(c.relnamespace::regnamespace::text,s.schemaname) coalesce_schemaname,s.* FROM pg_stat_all_tables s LEFT JOIN pg_class c ON (s.relid=c.reltoastrelid))
      ,i AS (SELECT COALESCE(c.relnamespace::regnamespace::text,s.schemaname) coalesce_schemaname,s.* FROM pg_stat_all_indexes s LEFT JOIN pg_class c ON (s.relid=c.reltoastrelid))
      ,td AS (SELECT COALESCE(c.relnamespace::regnamespace::text,s.schemaname) coalesce_schemaname,s.* FROM pg_statio_all_tables s LEFT JOIN pg_class c ON (s.relid=c.reltoastrelid))
      ,id AS (SELECT COALESCE(c.relnamespace::regnamespace::text,s.schemaname) coalesce_schemaname,s.* FROM pg_statio_all_indexes s LEFT JOIN pg_class c ON (s.relid=c.reltoastrelid))
      ,s AS (SELECT * FROM pg_statio_all_sequences)
      ,f AS (SELECT * FROM pg_stat_user_functions)
  INSERT INTO ds_tmpDiffStats
    SELECT p_run,statement_timestamp(),'60 Database','Stat:'||stat_name, units, coalesce(events,0), cum_time_ms FROM (
      SELECT 'xact_commit' stat_name,'xact' units,xact_commit::numeric events,NULL::numeric cum_time_ms FROM d
        UNION ALL
      SELECT 'xact_rollback','xact',xact_rollback,NULL FROM d
        UNION ALL
      SELECT 'blks_read','blocks',blks_read,blk_read_time FROM d
        UNION ALL
      SELECT 'blks_hit','blocks',blks_hit,NULL FROM d 
        UNION ALL
      SELECT 'tup_returned','tuples',tup_returned,NULL FROM d
        UNION ALL
      SELECT 'tup_fetched','tuples',tup_fetched,NULL FROM d
        UNION ALL
      SELECT 'tup_inserted','tuples',tup_inserted,NULL FROM d
        UNION ALL
      SELECT 'tup_updated','tuples',tup_updated,NULL FROM d
        UNION ALL
      SELECT 'tup_deleted','tuples',tup_deleted,NULL FROM d
        UNION ALL
      SELECT 'temp_files' stat_name,'files' units,temp_files::numeric events,NULL::numeric cum_time_ms FROM d
        UNION ALL
      SELECT 'temp_bytes','bytes',temp_bytes,NULL FROM d
        UNION ALL
      SELECT 'deadlocks','deadlocks',deadlocks,NULL FROM d
        UNION ALL
      SELECT 'blk_write_time','time',p_run,blk_write_time FROM d
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':seq_scan','scans',seq_scan,NULL FROM t
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':seq_tup_read','tuples',seq_tup_read,NULL FROM t
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':idx_scan','scans',idx_scan,NULL FROM t
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':idx_tup_fetch','tuples',idx_tup_fetch,NULL FROM t
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':n_tup_ins','tuples',n_tup_ins,NULL FROM t
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':n_tup_upd','tuples',n_tup_upd,NULL FROM t
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':n_tup_del','tuples',n_tup_del,NULL FROM t
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':n_tup_hot_upd','tuples',n_tup_hot_upd,NULL FROM t
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':vacuum_count','exec',vacuum_count,NULL FROM t
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':autovacuum_count','exec',autovacuum_count,NULL FROM t
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':analyze_count','exec',analyze_count,NULL FROM t
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':autoanalyze_count','exec',autoanalyze_count,NULL FROM t
        UNION ALL
      SELECT coalesce_schemaname||':'||indexrelname||':idx_scan','scans',idx_scan,NULL FROM i
        UNION ALL
      SELECT coalesce_schemaname||':'||indexrelname||':idx_tup_read','tid',idx_tup_read,NULL FROM i
        UNION ALL
      SELECT coalesce_schemaname||':'||indexrelname||':idx_tup_fetch','tuples',idx_tup_fetch,NULL FROM i
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':heap_blks_read','blocks',heap_blks_read,NULL FROM td
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':heap_blks_hit','blocks',heap_blks_hit,NULL FROM td
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':idx_blks_read','blocks',idx_blks_read,NULL FROM td
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':idx_blks_hit','blocks',idx_blks_hit,NULL FROM td
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':toast_blks_read','blocks',toast_blks_read,NULL FROM td
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':toast_blks_hit','blocks',toast_blks_hit,NULL FROM td
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':tidx_blks_read','blocks',tidx_blks_read,NULL FROM td
        UNION ALL
      SELECT coalesce_schemaname||':'||relname||':tidx_blks_hit','blocks',tidx_blks_hit,NULL FROM td
        UNION ALL
      SELECT coalesce_schemaname||':'||indexrelname||':idx_blks_read','blocks',idx_blks_read,NULL FROM id
        UNION ALL
      SELECT coalesce_schemaname||':'||indexrelname||':idx_blks_hit','blocks',idx_blks_hit,NULL FROM id
        UNION ALL
      SELECT schemaname||'.'||relname||':seq:blks_read','blocks',blks_read,NULL FROM s
        UNION ALL
      SELECT schemaname||'.'||relname||':seq:blks_hit','blocks',blks_hit,NULL FROM s
        UNION ALL
      SELECT schemaname||'.'||funcname||':total_time:calls','exec',calls,total_time FROM f
        UNION ALL
      SELECT schemaname||'.'||funcname||':self_time:calls','exec',calls,self_time FROM f
    ) q;

  WITH b AS (SELECT * FROM pg_stat_bgwriter)
  INSERT INTO ds_tmpDiffStats
    SELECT p_run,statement_timestamp(),'70 Instance','Stat:'||stat_name, units, coalesce(events,0), cum_time_ms FROM (
      SELECT 'checkpoints_timed' stat_name,'checkpoints' units, checkpoints_timed::numeric events,NULL::numeric cum_time_ms FROM b
        UNION ALL
      SELECT 'checkpoints_req','checkpoints',checkpoints_req,NULL FROM b
        UNION ALL
      SELECT 'buffers_checkpoint','blocks',buffers_checkpoint,NULL FROM b
        UNION ALL
      SELECT 'buffers_clean','blocks',buffers_clean,NULL FROM b
        UNION ALL
      SELECT 'maxwritten_clean','blocks',maxwritten_clean,NULL FROM b
        UNION ALL
      SELECT 'buffers_backend','blocks',buffers_backend,NULL FROM b
        UNION ALL
      SELECT 'buffers_alloc','blocks',buffers_alloc,NULL FROM b
        UNION ALL
      SELECT 'pg_current_xact_id','xid',age('3'::xid),NULL
    ) q;

  WITH c AS (SELECT * FROM pg_stat_database_conflicts WHERE datname=current_database())
  INSERT INTO ds_tmpDiffStats
    SELECT p_run,statement_timestamp(),'60 Database','Stat:'||stat_name, units, coalesce(events,0), cum_time_ms FROM (
      SELECT 'confl_tablespace' stat_name,'queries' units, confl_tablespace::numeric events,NULL::numeric cum_time_ms FROM c
        UNION ALL
      SELECT 'confl_lock','queries',confl_lock,NULL FROM c
        UNION ALL
      SELECT 'confl_snapshot','queries',confl_snapshot,NULL FROM c
        UNION ALL
      SELECT 'confl_bufferpin','queries',confl_bufferpin,NULL FROM c
        UNION ALL
      SELECT 'confl_deadlock','queries',confl_deadlock,NULL FROM c
    ) q;

  WITH b AS (SELECT * FROM pg_stat_bgwriter)
  INSERT INTO ds_tmpDiffStats
    SELECT p_run,statement_timestamp(),'70 Instance','Stat:'||stat_name, units, coalesce(events,0), cum_time_ms FROM (
      SELECT 'buffers_backend_fsync' stat_name,'exec' units, buffers_backend_fsync::numeric events,NULL::numeric cum_time_ms FROM b
        UNION ALL
      SELECT 'checkpoint_write_time' stat_name,'time' units, p_run::numeric events,checkpoint_write_time::numeric cum_time_ms FROM b
        UNION ALL
      SELECT 'checkpoint_sync_time','time',p_run,checkpoint_sync_time FROM b
    ) q;

  -- PostgreSQL 9.5 statistics
  IF v_server_version_num>=90500 THEN
    INSERT INTO ds_tmpDiffStats
      SELECT p_run,statement_timestamp(),'70 Instance','Stat:'||stat_name, units, coalesce(events,0), cum_time_ms FROM (
        SELECT 'pg_current_multixact_id' stat_name,'mxid' units,mxid_age('1')::numeric events,NULL::numeric cum_time_ms
      ) q;
  END IF;

  -- PostgreSQL 10 statistics
  IF v_server_version_num>=100000 THEN
    BEGIN
      INSERT INTO ds_tmpDiffStats
        SELECT p_run,statement_timestamp(),'70 Instance','Stat:'||stat_name, units, coalesce(events,0), cum_time_ms FROM (
          SELECT 'pg_current_wal_lsn' stat_name,'bytes' units,pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0'::pg_lsn)::numeric events,NULL::numeric cum_time_ms
        ) q;
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; -- WAL control functions cannot be executed when wal_level < logical
    END;

    BEGIN
      INSERT INTO ds_tmpDiffStats
        SELECT p_run,statement_timestamp(),'70 Instance','Stat:'||stat_name, units, coalesce(events,0), cum_time_ms FROM (
          SELECT 'pg_last_wal_replay_lsn' stat_name,'bytes' units,pg_wal_lsn_diff(pg_last_wal_replay_lsn(), '0/0'::pg_lsn)::numeric events,NULL::numeric cum_time_ms
        ) q;
    EXCEPTION WHEN feature_not_supported THEN NULL; -- Function pg_last_xlog_replay_location() is currently not supported for Aurora
    END;
  END IF;

  -- PostgreSQL 13 statistics
  IF v_server_version_num>=130000 THEN
    WITH s AS (SELECT * FROM pg_stat_slru)
    INSERT INTO ds_tmpDiffStats
      SELECT p_run,statement_timestamp(),'70 Instance','Stat:'||stat_name, units, coalesce(events,0), cum_time_ms FROM (
        SELECT 'slru:blks_zeroed' stat_name,'blocks' units,blks_zeroed::numeric events,NULL::numeric cum_time_ms FROM s
          UNION ALL
        SELECT 'slru:blks_hit','blocks',blks_hit,NULL FROM s
          UNION ALL
        SELECT 'slru:blks_read','blocks',blks_read,NULL FROM s
          UNION ALL
        SELECT 'slru:blks_written','blocks',blks_written,NULL FROM s
          UNION ALL
        SELECT 'slru:blks_exists','blocks',blks_exists,NULL FROM s
          UNION ALL
        SELECT 'slru:flushes','exec',flushes,NULL FROM s
          UNION ALL
        SELECT 'slru:truncates','exec',truncates,NULL FROM s
      ) q;
  END IF;

  -- PostgreSQL 14 statistics
  IF v_server_version_num>=140000 THEN
    WITH d AS (SELECT * FROM pg_stat_database WHERE datname=current_database())
    INSERT INTO ds_tmpDiffStats
      SELECT p_run,statement_timestamp(),'60 Database','Stat:'||stat_name, units, coalesce(events,0), cum_time_ms FROM (
        SELECT 'session_time' stat_name,'time' units,session_time::numeric events,NULL::numeric cum_time_ms FROM d
          UNION ALL
        SELECT 'active_time','time',p_run,active_time FROM d
          UNION ALL
        SELECT 'idle_in_transaction_time','time',p_run,idle_in_transaction_time FROM d
          UNION ALL
        SELECT 'sessions','conn',sessions,NULL FROM d
          UNION ALL
        SELECT 'sessions_abandoned','connections',sessions_abandoned,NULL FROM d
          UNION ALL
        SELECT 'sessions_fatal','connections',p_run,sessions_fatal FROM d
          UNION ALL
        SELECT 'sessions_killed','connections',p_run,sessions_killed FROM d
      ) q;

    BEGIN
      WITH w AS (SELECT * FROM pg_stat_wal)
      INSERT INTO ds_tmpDiffStats
        SELECT p_run,statement_timestamp(),'70 Instance','Stat:'||stat_name, units, coalesce(events,0), cum_time_ms FROM (
          SELECT 'wal_records' stat_name,'records' units,wal_records::numeric events,NULL::numeric cum_time_ms FROM w
            UNION ALL
          SELECT 'wal_fpi','blocks',wal_fpi,NULL FROM w
            UNION ALL
          SELECT 'wal_bytes','bytes',wal_bytes,NULL FROM w
            UNION ALL
          SELECT 'wal_buffers_full','exec',wal_buffers_full,NULL FROM w
            UNION ALL
          SELECT 'wal_write','exec',wal_write,wal_write_time FROM w
            UNION ALL
          SELECT 'wal_sync','exec',wal_sync,wal_sync_time FROM w
        ) q;
    EXCEPTION WHEN feature_not_supported THEN NULL;  -- pg_stat_get_wal() is not supported on Aurora
    END;
  END IF;

  -- Linux statistics via pg_proctab extension, if available
  BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_proctab;

    WITH p AS (SELECT * FROM pg_proctab() WHERE pid=pg_backend_pid())
    INSERT INTO ds_tmpDiffStats
      SELECT p_run,statement_timestamp(),'20 Session','Stat:LinuxProcess:'||stat_name, units, coalesce(events,0), cum_time_ms FROM (
        SELECT 'stat:utime' stat_name,'time' units,p_run::numeric events,utime::numeric*10 cum_time_ms FROM p
          UNION ALL
        SELECT 'stat:stime','time',p_run,stime*10 FROM p
          UNION ALL
        SELECT 'stat:cutime','time',p_run,cutime*10 FROM p
          UNION ALL
        SELECT 'stat:cstime','time',p_run,cstime*10 FROM p
          UNION ALL
        SELECT 'stat:minflt','pages',minflt,NULL FROM p
          UNION ALL
        SELECT 'stat:cminflt','pages',cminflt,NULL FROM p
          UNION ALL
        SELECT 'stat:majflt','pages',majflt,NULL FROM p
          UNION ALL
        SELECT 'stat:cmajflt','pages',cmajflt,NULL FROM p
          UNION ALL
        SELECT 'io:rchar','bytes',rchar,NULL FROM p
          UNION ALL
        SELECT 'io:wchar','bytes',wchar,NULL FROM p
          UNION ALL
        SELECT 'io:syscr','exec',syscr,NULL FROM p
          UNION ALL
        SELECT 'io:syscw','exec',syscw,NULL FROM p
          UNION ALL
        SELECT 'io:read_bytes','bytes',reads,NULL FROM p
          UNION ALL
        SELECT 'io:write_bytes','bytes',writes,NULL FROM p
          UNION ALL
        SELECT 'io:canceled_write_bytes','bytes',cwrites,NULL FROM p
      ) q;

    WITH c AS (SELECT * FROM pg_cputime())
        ,d AS (SELECT * FROM pg_diskusage())
    INSERT INTO ds_tmpDiffStats
      SELECT p_run,statement_timestamp(),'80 System','Stat:Linux:'||stat_name, units, coalesce(events,0), cum_time_ms FROM (
        SELECT 'cpu:user' stat_name,'time' units,p_run::numeric events,"user"::numeric*10 cum_time_ms FROM pg_cputime()
          UNION ALL
        SELECT 'cpu:nice (DB Instance @AWS)','time',p_run,nice*10 FROM c
          UNION ALL
        SELECT 'cpu:system','time',p_run,system*10 FROM c
          UNION ALL
        SELECT 'cpu:idle','time',p_run,idle*10 FROM c
          UNION ALL
        SELECT 'cpu:iowait','time',p_run,iowait*10 FROM c
          UNION ALL
        SELECT 'diskstats:'||devname||':reads_completed','exec',reads_completed,readtime FROM d
          UNION ALL
        SELECT 'diskstats:'||devname||':reads_merged','exec',reads_merged,NULL FROM d
          UNION ALL
        SELECT 'diskstats:'||devname||':sectors_read','sectors',sectors_read,readtime FROM d
          UNION ALL
        SELECT 'diskstats:'||devname||':writes_completed','exec',writes_completed,writetime FROM d
          UNION ALL
        SELECT 'diskstats:'||devname||':writes_merged','exec',writes_merged,NULL FROM d
          UNION ALL
        SELECT 'diskstats:'||devname||':sectors_written','sectors',sectors_written,writetime FROM d
          UNION ALL
        SELECT 'diskstats:'||devname||':io_time','time',p_run,iotime FROM d
          UNION ALL
        SELECT 'diskstats:'||devname||':weighted_io_time','time',p_run,totaliotime FROM d
      ) q;
  EXCEPTION WHEN undefined_file   -- pg_proctab is not available
      OR feature_not_supported    -- pg_proctab is not available
      OR insufficient_privilege   -- not running as superuser
    THEN NULL;
  END;

  -- Extra Aurora statistics, if available
  BEGIN
    INSERT INTO ds_tmpDiffStats
      SELECT p_run,statement_timestamp(),'20 Session','Wait:'||type_name||':'||event_name, 'waits', coalesce(waits,0), coalesce(wait_time::numeric/1000,0)
        FROM aurora_stat_wait_event()
          NATURAL JOIN aurora_stat_wait_type()
          NATURAL LEFT JOIN aurora_stat_backend_waits(pg_backend_pid());

    INSERT INTO ds_tmpDiffStats
      SELECT p_run,statement_timestamp(),'70 Instance','Wait:'||type_name||':'||event_name, 'waits', coalesce(waits,0), coalesce(wait_time::numeric/1000,0)
        FROM aurora_stat_wait_event()
          NATURAL JOIN aurora_stat_wait_type()
          NATURAL LEFT JOIN aurora_stat_system_waits();

    WITH d AS (SELECT oid FROM pg_database WHERE datname=current_database())
        ,a AS (SELECT * FROM d,aurora_stat_dml_activity(d.oid))
    INSERT INTO ds_tmpDiffStats
      SELECT p_run,statement_timestamp(),'70 Instance','Stat:Aurora:'||stat_name, units, coalesce(events,0), cum_time_ms FROM (
        SELECT 'select_count' stat_name,'sql' units,select_count::numeric events,select_latency_microsecs::numeric/1000 cum_time_ms FROM a
          UNION ALL
        SELECT 'insert_count','sql',insert_count,insert_latency_microsecs/1000 FROM a
          UNION ALL
        SELECT 'update_count','sql',update_count,update_latency_microsecs/1000 FROM a
          UNION ALL
        SELECT 'delete_count','sql',delete_count,delete_latency_microsecs/1000 FROM a
      ) q;
  EXCEPTION WHEN undefined_function THEN NULL;  -- not on Aurora
  END;

  RETURN p_run;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION ds_start() RETURNS int AS $$
BEGIN
  CREATE TEMPORARY TABLE IF NOT EXISTS ds_tmpDiffStats (run int, tm timestamp with time zone, 
          scope text, name text, units text, count numeric, cum_time_ms numeric);
  TRUNCATE TABLE ds_tmpDiffStats;

  RETURN ds_insert(0);
END; 
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION ds_capture() RETURNS int AS $$
DECLARE
  prev_run numeric;
BEGIN
  SELECT MAX(run) INTO prev_run FROM ds_tmpDiffStats;
  CASE prev_run
    WHEN NULL THEN
      RAISE NOTICE 'ERROR: no initial data; execute ds_start() to start';
      RETURN NULL;
    WHEN 0 THEN
      RETURN ds_insert(1);
    WHEN 1 THEN
      RETURN ds_insert(2);
  END CASE;

  RAISE NOTICE 'ERROR: already captured data for two runs; execute ds_report_diff() or use ds_start() to start over';
  RETURN NULL;
END; 
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION ds_report(IN global_scope boolean DEFAULT TRUE,IN all_rows boolean DEFAULT FALSE)
  RETURNS TABLE (scope text,
    name text,
    units text,
    count numeric,   
    cum_ms numeric,
    avg_ms numeric)
AS $$
DECLARE
  time_run1 numeric;
  prev_run numeric;
BEGIN
  SELECT MAX(run) INTO prev_run FROM ds_tmpDiffStats;
  CASE prev_run
    WHEN NULL THEN
      RAISE NOTICE 'ERROR: no initial data; execute ds_start() before ds_report()';
      RETURN;
    WHEN 0 THEN
      SELECT ds_insert(1) INTO prev_run;
    WHEN 1 THEN
      NULL;
    WHEN 2 THEN
      RAISE NOTICE 'WARNING: this report excludes data from the second run';
  END CASE;

  SELECT EXTRACT(EPOCH from r1.tm-r0.tm)*1000 INTO time_run1 FROM 
    (SELECT tm FROM ds_tmpDiffStats WHERE run=0 LIMIT 1) r0, 
    (SELECT tm FROM ds_tmpDiffStats WHERE run=1 LIMIT 1) r1
  ;

  RAISE NOTICE 'Total time of run: % ms', time_run1;

  RETURN QUERY
  WITH diff AS (
    SELECT s.run AS q_run, s.scope q_scope, s.name q_name, s.units q_units
      ,s.count - LAG(s.count) OVER (PARTITION BY s.scope,s.name,s.units ORDER BY run) AS q_count
      ,s.cum_time_ms - LAG(s.cum_time_ms) OVER (PARTITION BY s.scope,s.name,s.units ORDER BY run) AS q_cum_time_ms
    FROM ds_tmpDiffStats s
    WHERE s.run<2
  ), summary AS (
    SELECT q_scope, q_name, q_units
      ,max(q_count) FILTER (WHERE q_run=1) AS q_count_1
      ,round(max(q_cum_time_ms) FILTER (WHERE q_run=1),3) AS q_cum_ms_1
      ,round(max(q_cum_time_ms/q_count) FILTER (WHERE q_run=1 AND q_count<>0),3) AS q_avg_ms_1
    FROM diff
    WHERE q_cum_time_ms>0 OR (q_count>0 AND q_units<>'time')
    GROUP BY q_scope, q_name, q_units
  )
  SELECT right(q_scope,-3), q_name, q_units, q_count_1, q_cum_ms_1, q_avg_ms_1
  FROM summary
  WHERE (q_scope < '50' OR global_scope)
    AND ((q_name NOT LIKE 'Stat:pg_catalog%' AND q_name NOT LIKE 'Stat:information_schema%' AND q_name NOT LIKE 'Stat:%:ds\_%' AND q_name NOT LIKE 'Stat:%.ds\_%' AND q_name NOT LIKE '%pg_toast_'||'ds_tmpdiffstats'::regclass::int||'%') OR all_rows)
  ORDER BY q_scope ASC
         , q_cum_ms_1 DESC NULLS LAST
         , q_count_1 DESC NULLS LAST;
END;
$$ LANGUAGE plpgsql;





CREATE OR REPLACE FUNCTION ds_report_diff(IN global_scope boolean DEFAULT TRUE,IN all_rows boolean DEFAULT FALSE,IN cnt_diff_pct_threshold numeric DEFAULT 0)
  RETURNS TABLE (scope text,
    name text,
    units text,
    count_1 numeric,   
    cum_ms_1 numeric,
    avg_ms_1 numeric,
    count_2 numeric,
    cum_ms_2 numeric,
    avg_ms_2 numeric,
    cnt_diff text)
AS $$
DECLARE
  time_run1 numeric;
  time_run2 numeric;
  prev_run numeric;
BEGIN
  SELECT MAX(run) INTO prev_run FROM ds_tmpDiffStats;
  CASE prev_run
    WHEN NULL THEN
      RAISE NOTICE 'ERROR: no initial data; execute ds_start() before ds_report()';
      RETURN;
    WHEN 0 THEN
      SELECT ds_insert(1) INTO prev_run;
    WHEN 1 THEN
      SELECT ds_insert(2) INTO prev_run;
    WHEN 2 THEN
      NULL;
  END CASE;

  SELECT EXTRACT(EPOCH from r1.tm-r0.tm)*1000 INTO time_run1 FROM 
    (SELECT tm FROM ds_tmpDiffStats WHERE run=0 LIMIT 1) r0, 
    (SELECT tm FROM ds_tmpDiffStats WHERE run=1 LIMIT 1) r1
  ;
  IF prev_run=2 THEN
    SELECT EXTRACT(EPOCH from r2.tm-r1.tm)*1000 INTO time_run2 FROM 
      (SELECT tm FROM ds_tmpDiffStats WHERE run=1 LIMIT 1) r1, 
      (SELECT tm FROM ds_tmpDiffStats WHERE run=2 LIMIT 1) r2
    ;
  END IF;

  RAISE NOTICE 'Total time run 1: % ms', time_run1;
  IF prev_run=2 THEN
    RAISE NOTICE 'Total time run 2: % ms', time_run2;
    RAISE NOTICE 'Run 1 total time is % %% of run 2 total time', round(100*time_run1/time_run2,1);
  END IF;

  RETURN QUERY
  WITH diff AS (
    SELECT s.run AS q_run, s.scope q_scope, s.name q_name, s.units q_units
      ,s.count - LAG(s.count) OVER (PARTITION BY s.scope,s.name,s.units ORDER BY run) AS q_count
      ,s.cum_time_ms - LAG(s.cum_time_ms) OVER (PARTITION BY s.scope,s.name,s.units ORDER BY run) AS q_cum_time_ms
    FROM ds_tmpDiffStats s
  ), summary AS (
    SELECT q_scope, q_name, q_units
      ,max(q_count) FILTER (WHERE q_run=1) AS q_count_1
      ,round(max(q_cum_time_ms) FILTER (WHERE q_run=1),3) AS q_cum_ms_1
      ,round(max(q_cum_time_ms/q_count) FILTER (WHERE q_run=1 AND q_count<>0),3) AS q_avg_ms_1
      ,max(q_count) FILTER (WHERE q_run=2) AS q_count_2
      ,round(max(q_cum_time_ms) FILTER (WHERE q_run=2),3) AS q_cum_ms_2
      ,round(max(q_cum_time_ms/q_count) FILTER (WHERE q_run=2 AND q_count<>0),3) AS q_avg_ms_2
    FROM diff
    WHERE q_cum_time_ms>0 OR (q_count>0 AND q_units<>'time')
    GROUP BY q_scope, q_name, q_units
  )
  SELECT right(q_scope,-3), q_name, q_units, q_count_1, q_cum_ms_1, q_avg_ms_1, q_count_2, q_cum_ms_2, q_avg_ms_2
    ,ROUND(ABS((1-q_count_1/CASE WHEN q_count_2>0 THEN q_count_2 ELSE null END)*100),1)||' %' q_cnt_diff
  FROM summary
  WHERE (COALESCE(ABS((1-q_count_1/CASE WHEN q_count_2>0 THEN q_count_2 ELSE null END))*100,100)>=cnt_diff_pct_threshold)
    AND (q_scope < '50' OR global_scope)
    AND ((q_name NOT LIKE 'Stat:pg_catalog%' AND q_name NOT LIKE 'Stat:information_schema%' AND q_name NOT LIKE 'Stat:%:ds\_%' AND q_name NOT LIKE 'Stat:%.ds\_%' AND q_name NOT LIKE '%pg_toast_'||'ds_tmpdiffstats'::regclass::int||'%') OR all_rows)
  ORDER BY q_scope ASC
         , COALESCE(q_cum_ms_2,0)+COALESCE(q_cum_ms_1,0) DESC
         , ABS((1-q_count_1/CASE WHEN q_count_2>0 THEN q_count_2 ELSE null END))*100 DESC NULLS LAST
         , COALESCE(q_count_2,0)+COALESCE(q_count_1,0) DESC;
END;
$$ LANGUAGE plpgsql;
