-module(client).
-export([handle/2, initial_state/3]).

-record(client_st, {
    gui,
    nick,
    server,
    channels = #{} % Maps ChannelName -> ChannelPid for direct communication.
}).

initial_state(Nick, GUIAtom, ServerAtom) ->
    #client_st{
        gui = GUIAtom,
        nick = Nick,
        server = ServerAtom,
        channels = #{}
    }.

% Join channel
handle(St, {join, Channel}) ->
    Server = St#client_st.server,
    Nick = St#client_st.nick,
    
    % Catch crashes to prevent client failure and notify GUI.
    Result = case catch genserver:request(Server, {join, Channel, self(), Nick}) of
        {'EXIT', _} -> {error, server_not_reached, "Server timed out"};
        timeout_error -> {error, server_not_reached, "Server timed out"};
        Other -> Other 
    end,
    
    case Result of
        {ok, ChannelPid} ->
            % Store ChannelPid for direct messaging.
            NewChannels = maps:put(Channel, ChannelPid, St#client_st.channels),
            {reply, ok, St#client_st{channels = NewChannels}};
        Error ->
            {reply, Error, St}
    end;

% Leave channel
handle(St, {leave, Channel}) ->
    ChannelPid = maps:get(Channel, St#client_st.channels, undefined),
    case ChannelPid of
        undefined -> 
            {reply, {error, user_not_joined, "You are not in this channel"}, St};
        _ ->
            % Leave the channel process directly.
            catch genserver:request(ChannelPid, {leave, self()}),
            NewChannels = maps:remove(Channel, St#client_st.channels),
            {reply, ok, St#client_st{channels = NewChannels}}
    end;

% Sending message (from GUI, to channel)
handle(St, {message_send, Channel, Msg}) ->
    Nick = St#client_st.nick, 
    ChannelPid = maps:get(Channel, St#client_st.channels, undefined),
    
    case ChannelPid of
        undefined -> 
            % Fallback: Check with main server if channel doesn't exist locally.
            Server = St#client_st.server,
            TryResult = catch genserver:request(Server, {message_send, Channel, self(), Nick, Msg}), 
            Result = case TryResult of
                {'EXIT', _} -> {error, server_not_reached, "Server timed out"};
                timeout_error -> {error, server_not_reached, "Server timed out"};
                {error, user_not_joined, "Channel does not exist"} -> 
                    {error, server_not_reached, "Channel does not exist"};
                Other -> Other 
            end,
            {reply, Result, St};
        _ ->
            % Concurrency: Send directly to the channel process. Bypasses main server.
            TryResult = catch genserver:request(ChannelPid, {message_send, self(), Nick, Msg}), 
            Result = case TryResult of
                {'EXIT', _} -> {error, server_not_reached, "Server timed out"};
                timeout_error -> {error, server_not_reached, "Server timed out"};
                Other -> Other 
            end,
            {reply, Result, St}
    end;

% Change nick
handle(St, {nick, NewNick}) ->
    Server = St#client_st.server,
    OldNick = St#client_st.nick,

    % Catch server timeouts gracefully.
    TryResult = catch genserver:request(Server, {nick, OldNick, NewNick, self()}),
    
    case TryResult of
        {'EXIT', _} -> {reply, {error, server_not_reached, "Server timed out"}, St};
        timeout_error -> {reply, {error, server_not_reached, "Server timed out"}, St};
        ok -> {reply, ok, St#client_st{nick = NewNick}}; 
        {error, nick_taken, _} -> {reply, {error, nick_taken, "Nick taken"}, St}; 
        OtherError -> {reply, OtherError, St}
    end;

% Get current nick
handle(St, whoami) ->
    {reply, St#client_st.nick, St} ;

% Incoming message (from channel, to GUI)
handle(St = #client_st{gui = GUI}, {message_receive, Channel, Nick, Msg}) ->
    % Forward channel broadcast to GUI.
    gen_server:call(GUI, {message_receive, Channel, Nick++"> "++Msg}),
    {reply, ok, St} ;

% Quit client
handle(St, quit) ->
    {reply, ok, St} ;

% Catch-all
handle(St, _Data) ->
    {reply, {error, not_implemented, "Client does not handle this command"}, St} .