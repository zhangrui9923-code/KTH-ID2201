%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. 9月 2025 21:41
%%%-------------------------------------------------------------------
-module(server).
-author("23229").

%% API
-export([start/1, start_concurrency/2, stop/0, stop_concurrency/0, bench/0, bench/3]).


start(Port) ->
  register(rudy, spawn(fun () -> rudy:init(Port) end)).

stop() ->
  exit(whereis(rudy), "time to die").


start_concurrency(N,Port) ->
  register(rudy_concurrency, spawn(fun () -> rudy_concurrency:init(N,Port) end)).


stop_concurrency() -> exit(whereis(rudy_concurrency), "time to die").


bench() ->
  Start = erlang:system_time(micro_seconds),
  test:run(100, localhost, 8080),
  Finish = erlang:system_time(micro_seconds),
  ExTime = Finish - Start,
  io:format("The requests spent ~w μs to finish ~n", [ExTime]).

bench(N, Host, Port) ->
  Start = erlang:system_time(micro_seconds),
  test:run(N, Host, Port),
  Finish = erlang:system_time(micro_seconds),
  ExTime = Finish - Start,
  io:format("The requests spent ~w μs to finish ~n", [ExTime]).


