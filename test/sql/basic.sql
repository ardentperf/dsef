create extension dsef;

create table dsef1 as select generate_series(1,1000) a;



select ds_start(); 

select regexp_replace("QUERY PLAN",'Version:.*','Version') from explain_analyze_full($$ select max(a) from dsef1 $$) limit 1;; 

select pg_sleep(0.5);
set client_min_messages=warning;
select distinct scope from ds_report() where scope in ('Database','Instance');



select ds_start(); 

select regexp_replace("QUERY PLAN",'Version:.*','Version') from explain_analyze_full($$ select max(a) from dsef1 $$) limit 1;; 

select ds_capture();

select regexp_replace("QUERY PLAN",'Version:.*','Version') from explain_analyze_full($$ select min(a) from dsef1 $$) limit 1;; 

select pg_sleep(0.5);
set client_min_messages=warning;
select distinct scope from ds_report_diff() where scope in ('Database','Instance');
