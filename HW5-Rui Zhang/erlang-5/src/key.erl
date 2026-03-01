%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 06. 10月 2025 23:54
%%%-------------------------------------------------------------------
-module(key).
-export([generate/0, between/3]).

%% Generate a random key between 1 and 1,000,000,000
generate() ->
  rand:uniform(1000000000).

%% Check if Key is in the interval (From, To]
%% Returns true if From < Key =< To (considering ring structure)
between(Key, From, To) ->
  if
    From < To ->
      (From < Key) andalso (Key =< To);
    From > To ->
      (From < Key) orelse (Key =< To);
    From == To ->
      true  % Full circle - everything is between
  end.