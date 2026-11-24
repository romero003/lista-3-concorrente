        -module(main).
        -export([start/0, server/1, user/4]).

        receivenotifications(_Id, 0, Recebidas) ->
            lists:reverse(Recebidas);
        receivenotifications(Id, Restantes, Recebidas) ->
            receive
                {notification, Nid, Text} ->
                    io:format("O usuario ~p recebeu [~p]: ~p~n", [Id, Nid, Text]),
                    receivenotifications(Id, Restantes - 1, [Nid | Recebidas])
            end.

        wait_ready([]) ->
            ok;
        wait_ready(Pendentes) ->
            receive
                {ready, Id} ->
                    wait_ready(lists:delete(Id, Pendentes))
            end.

        wait_finished([], Resultados) ->
            Resultados;
        wait_finished(Pendentes, Resultados) ->
            receive
                {finished, Id, Recebidas} ->
                    wait_finished(lists:delete(Id, Pendentes), Resultados#{Id => Recebidas})
            end.

        start() ->
            CoorPid = self(),
            SPid = spawn(?MODULE, server, [#{}]),
            Users = [u1, u2, u3],
            Mensagens = [{1, "Nova mensagem"}, {2, "Última mensagem"}],
            TotalEsperadoPorUser = length(Mensagens),

            [spawn(?MODULE, user, [Id, SPid, CoorPid, TotalEsperadoPorUser]) || Id <- Users],

            wait_ready(Users),

            [SPid ! {notify, Nid, Text} || {Nid, Text} <- Mensagens],

            Resultados = wait_finished(Users, #{}),

            SPid ! {stop, CoorPid},
            receive
                {stopped, SPid} ->
                    ok
            end,

            EsperadosIds = [Nid || {Nid, _} <- Mensagens],
            TotalObtido = lists:foldl(
                fun(Id, Acc) ->
                    Obtidos = lists:sort(maps:get(Id, Resultados)),
                    Status = case Obtidos =:= EsperadosIds of
                        true -> "OK";
                        false -> "ERRO"
                    end,
                    io:format("~p: esperado ~w, obtido ~w -> ~s~n", [Id, EsperadosIds, Obtidos, Status]),
                    Acc + length(Obtidos)
                end,
                0,
                Users
            ),
            TotalEsperado = length(Users) * TotalEsperadoPorUser,
            io:format("Total de entregas: esperado ~p, obtido ~p~n", [TotalEsperado, TotalObtido]),
            ok.

        user(Id, SPid, CoorPid, TotalEsperado) ->
            SPid ! {register, Id, self()},
            receive
                {registered, Id} ->
                    io:format("Usuario ~p registrado~n", [Id]),
                    CoorPid ! {ready, Id}
            end,

            Recebidas = receivenotifications(Id, TotalEsperado, []),

            SPid ! {unregister, Id, self()},
            receive
                {unregistered, Id} ->
                    io:format("Usuario ~p cancelou o registro~n", [Id])
            end,

            CoorPid ! {finished, Id, Recebidas}.

        server(Users) ->
            receive
                {stop, CoorPid} ->
                    io:format("Encerrando ~n"),
                    CoorPid ! {stopped, self()};

                {register, Id, UPid} ->
                    UPid ! {registered, Id},
                    server(Users#{Id => UPid});

                {notify, Nid, Text} ->
                    [UPid ! {notification, Nid, Text} || UPid <- maps:values(Users)],
                    server(Users);

                {unregister, Id, UPid} ->
                    UPid ! {unregistered, Id},
                    server(maps:remove(Id, Users))
            end.