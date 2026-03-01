%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. 9月 2025 21:44
%%%-------------------------------------------------------------------
-module(test).
-author("23229").

%% API
-export([bench/3,run/3]).

bench(N, Host, Port) ->
  Start = erlang:system_time(micro_seconds),
  run(N, Host, Port),
  Finish = erlang:system_time(micro_seconds),
  ExTime = Finish - Start,
  io:format("The requests spent ~w μs to finish ~n", [ExTime]).
run(N, Host, Port)->
  if
    N == 0->
      ok;
    true->
      request(Host, Port),
      run(N-1, Host, Port)
  end.
request(Host, Port)->
  Opt = [list, {active, false}, {reuseaddr, true}],
  {ok, Server} = gen_tcp:connect(Host, Port, Opt),
  gen_tcp:send(Server, http:get("foo")),
  Recv = gen_tcp:recv(Server, 0),
  case Recv of
    {ok, _}->
      ok;
    {error, Error}->
      io:format("test: error: ~w~n", [Error])
  end,
  gen_tcp:close(Server).


