%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 06. 10月 2025 23:56
%%%-------------------------------------------------------------------
-module(storage).
-export([create/0, add/3, lookup/2, split/3, merge/2]).

%% Create an empty store
create() ->
  [].

%% Add a key-value pair to the store
add(Key, Value, Store) ->
  [{Key, Value} | Store].

%% Lookup a key in the store
lookup(Key, Store) ->
  lists:keyfind(Key, 1, Store).

%% Split store: keep keys in (From, To], return rest
split(From, To, Store) ->
  lists:partition(
    fun({Key, _Value}) ->
      key:between(Key, From, To)
    end,
    Store).

%% Merge a list of entries into store
merge(Entries, Store) ->
  lists:append(Entries, Store).