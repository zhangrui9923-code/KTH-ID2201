%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. 9月 2025 21:22
%%%-------------------------------------------------------------------
-module(rudy).
-author("23229").

%% API
-export([init/1,start/1, stop/0]).

init(Port)->
  Opt = [list, {active, false}, {reuseaddr, true},{backlog,2048}],
  case gen_tcp:listen(Port, Opt) of
    {ok, Listen}->
      handler(Listen),
      gen_tcp:close(Listen),
      ok;
    {error, Error}->
      error
  end.

handler(Listen)->
  case gen_tcp:accept(Listen) of
    {ok, Client}->
      request(Client),
      handler(Listen);
    {error, Error}->
      error
  end.

request(Client)->
  Recv = gen_tcp:recv(Client, 0),
  case Recv of
    {ok, Str}->
      Request = http:parse_request(Str),
      Response = reply(Request),
      gen_tcp:send(Client, Response);
    {error, Error}->
      io:format("rudy: error: ~w~n", [Error])
  end,
  gen_tcp:close(Client).

reply({{get, URI, _}, _, _})->
  timer:sleep(40),
  http:ok(URI).


start(Port)->
  register(rudy, spawn(fun()-> init(Port) end)).
stop()->
  exit(whereis(rudy), "time to die").