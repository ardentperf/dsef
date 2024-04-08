ALTER EXTENSION dsef ADD FUNCTION ds_version();
ALTER EXTENSION dsef ADD FUNCTION ds_set(text);
ALTER EXTENSION dsef ADD FUNCTION explain_analyze_full(text,text,boolean);
ALTER EXTENSION dsef ADD FUNCTION ds_insert(int);
ALTER EXTENSION dsef ADD FUNCTION ds_start();
ALTER EXTENSION dsef ADD FUNCTION ds_capture();
ALTER EXTENSION dsef ADD FUNCTION ds_report(boolean,boolean);
ALTER EXTENSION dsef ADD FUNCTION ds_report_diff(boolean,boolean,numeric);
