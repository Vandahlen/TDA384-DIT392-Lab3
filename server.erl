-module(server).
-export([start/1,stop/1]).

-record(serverState, {
    channels = #{},
    nicks = #{}
}).

% Start a new server process with the given name
% Do not change the signature of this function.
start(ServerAtom) ->
  genserver:start(ServerAtom, #serverState{channels = #{},nicks = #{} }, fun loop/2).

% Stop the server process registered to the given name,
% together with any other associated processes
stop(ServerAtom) ->
   genserver:stop(ServerAtom).


loop(State, Request) ->
    case Request of

    {join, Channel, Pid, Nick} ->

        Channels = State#serverState.channels,
        Nicks = State#serverState.nicks,

        CurrentUsers = maps:get(Channel, Channels, []),
        case lists:member(Pid, CurrentUsers) of
            true ->
                {reply, {error, user_already_joined, "You are already in this channel"}, State};
            false ->
                NewUsers = [Pid | CurrentUsers],
                NewChannels = maps:put(Channel, NewUsers, Channels),
                NewNicks = maps:put(Nick, Pid, Nicks),
                {reply, ok, State#serverState{channels = NewChannels, nicks = NewNicks}}
        end;

    {leave, Channel, Pid} ->

        Channels = State#serverState.channels,

        case maps:is_key (Channel, Channels) of
            false ->
                {reply, {error, user_not_joined, "..."}, State};
            true ->
                CurrentUsers = maps:get(Channel, Channels),
                case lists:member(Pid, CurrentUsers) of
                    false ->
                        {reply, {error, user_not_joined, "..."}, State};
                    true ->
                        NewUsers = lists:delete(Pid, CurrentUsers),
                        NewChannels = maps:put(Channel, NewUsers, Channels),
                        {reply, ok, State#serverState{channels = NewChannels}}
                end
        end;
    
    {nick, OldNick, NewNick, Pid} ->
        Nicks = State#serverState.nicks,
        
        case maps:is_key(NewNick, Nicks) of
            true ->
                {reply, {error, nick_taken, "Nick already taken"}, State};
            false ->
                NicksCleaned = maps:remove(OldNick, Nicks),
                
                NewNicks = maps:put(NewNick, Pid, NicksCleaned),

                {reply, ok, State#serverState{nicks = NewNicks}}
        end;

  {message_send, TargetChannel, Pid, Nick, Msg} ->

        Channels = State#serverState.channels,
        
        case maps:find(TargetChannel, Channels) of
            error ->
                {reply, {error, user_not_joined, "Channel does not exist"}, State};
            {ok, Users} ->
                case lists:member(Pid, Users) of
                    false ->
                        {reply, {error, user_not_joined, "You are not in this channel"}, State};
                    true ->
                        ServerPid = self(),
                        spawn(fun() ->
                            Recipients = lists:delete(Pid, Users),
                            Sendmsg = fun(ReceiverPid) ->
                                ReceiverPid ! {request, ServerPid, make_ref(), {message_receive, TargetChannel, Nick, Msg}}
                            end,
                            lists:foreach(Sendmsg, Recipients)
                        end),
                        
                        {reply, ok, State}
                end
        end;
    stop ->
        {reply, ok, State};
    
    _ ->
            {reply, {error, unknown_command, "Server received unknown command"}, State}
end.