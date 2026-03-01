@echo off
REM Script to run multiple Erlang shells with test commands
REM Each shell will compile and run the test benchmark

REM Define the Rudy project path as a variable
set RUDY_PATH=D:\java tool\IDEA project\erlang-1\src

echo Starting 6 Erlang shells for testing...

REM Start the first Erlang shell in a new window
start cmd /k "cd /d %RUDY_PATH% && erl -eval " io:format(\"Shell 1 test starting~n\"), Timer = server:bench(100,\"localhost\", 8080), io:format(\"Time: ~p microseconds~n\", [Timer])." "



REM Start the second Erlang shell in a new window
start cmd /k "cd /d %RUDY_PATH% && erl -eval " io:format(\"Shell 2 test starting~n\"), Timer = server:bench(100,\"localhost\", 8080), io:format(\"Time: ~p microseconds~n\", [Timer])." "



REM Start the third Erlang shell in a new window
start cmd /k "cd /d %RUDY_PATH% && erl -eval " io:format(\"Shell 3 test starting~n\"), Timer = server:bench(100,\"localhost\", 8080), io:format(\"Time: ~p microseconds~n\", [Timer])." "



REM Start the fourth Erlang shell in a new window
start cmd /k "cd /d %RUDY_PATH% && erl -eval " io:format(\"Shell 4 test starting~n\"), Timer = server:bench(100,\"localhost\", 8080), io:format(\"Time: ~p microseconds~n\", [Timer])." "



REM Start the fifth Erlang shell in a new window
start cmd /k "cd /d %RUDY_PATH% && erl -eval " io:format(\"Shell 5 test starting~n\"), Timer = server:bench(100,\"localhost\", 8080), io:format(\"Time: ~p microseconds~n\", [Timer])." "



REM Start the sixth Erlang shell in a new window
start cmd /k "cd /d %RUDY_PATH% && erl -eval " io:format(\"Shell 6 test starting~n\"), Timer = server:bench(100,\"localhost\", 8080), io:format(\"Time: ~p microseconds~n\", [Timer])." "



