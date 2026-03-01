%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 07. 9月 2025 20:58
%%%-------------------------------------------------------------------
-module(rudy_concurrency).
-author("23229").

%% API
-export([init/2]).

init(N,Port) ->
  Opt = [list, {active, false}, {reuseaddr, true},{backlog,2048}],
  case gen_tcp:listen(Port, Opt) of
    {ok, Listen} ->
      io:format("Server started on port ~w~n",[Port]),
      generate_handlers(N,Listen),
      keep_alive();
    {error, _Error} ->
      error
  end.

generate_handlers(0,_) -> ok;
generate_handlers(N,Listen) when N>0 ->
  spawn_link(fun() ->
    io:format("Handler ~p started~n",[N]),
    handler(N,Listen)
             end),
  generate_handlers(N-1,Listen).



handler(N,Listen) ->
  case gen_tcp:accept(Listen) of
    {ok, Client} ->
      request(Client),
      handler(N,Listen);
    {error, _Error} ->
      error
  end.

request(Client) ->
  Recv = gen_tcp:recv(Client, 0),
  case Recv of
    {ok, Str} ->
      Request = http:parse_request(Str),
      Response = reply(Request),
      gen_tcp:send(Client, Response);
    {error, Error} ->
      io:format("rudy: error: ~w~n", [Error])
  end,
  gen_tcp:close(Client).

reply({{get, URI, _}, _, _}) ->
  timer:sleep(40),
  http:ok(URI).

keep_alive() ->
  timer:sleep(1000),
  keep_alive().
