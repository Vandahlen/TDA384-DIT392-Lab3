-module(server).
-export([start/1,stop/1]).

-record(serverState, {
    channels = #{}
}).

% Start a new server process with the given name
% Do not change the signature of this function.
start(ServerAtom) ->
  genserver:start(ServerAtom, #serverState{}, fun loop/2).

% Stop the server process registered to the given name,
% together with any other associated processes
stop(ServerAtom) ->
   genserver:stop(ServerAtom).


loop(State, Request) ->
    case Request of

    {join, Channel, Pid} ->

        Channels = State#serverState.channels,

        CurrentUsers = maps:get(Channels, Channels, []),

        case list:members(Pid, CurrentUsers) of
            true ->
                {reply, {error, user_already_joined, "You are already in this channel"}, State};
            false ->
                NewUsers = [Pid | CurrentUsers],
                NewChannels = maps:put(Channel, NewUsers, Channels),
                {reply, ok, State#serverState{channels = NewChannels}}
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

    {message_send, Channel, Pid, Nick, Msg} ->

        Channels = State#serverState.channels,
        
        case maps:find (Channel, Channels) of
            error ->
                {reply, {error, user_not_joined, "Channel does not exist"}, State};
            {ok, Users} ->
                case lists:member(Pid, Users) of
                    false ->
                        {reply, {error, user_not_joined, "You are not in this channel"}, State};
                    true ->
                        sendmsg = fun(ReceiverPid) ->
                            ReceiverPid ! {request, self(), make_ref(), {message_receive, Channel, Nick, Msg}}
                end,
                lists:foreach(sendmsg, Users),
                {reply, ok, State}
            end
        end;
    
    _ ->
            {reply, {error, unknown_command, "Server received unknown command"}, State}
end.