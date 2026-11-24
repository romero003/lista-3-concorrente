# Lista de Exercícios 3 — Programação Concorrente (Erlang)

**Aluno:** Romero Rêgo Cavalcanti Filho  
**Assunto:** Erlang — Comunicação por Passagem de Mensagens  
**Questão Escolhida:** Questão 5 – Servidor de notificações para usuários

---

## 1. Situação-Problema

Um sistema precisa distribuir notificações para usuários conectados. Em vez de cada componente conhecer todos os destinatários, um processo servidor mantém a lista de usuários registrados em seu próprio estado interno e encaminha as mensagens recebidas exclusivamente por troca de mensagens.

---

## 2. Instalação de Dependências, Compilação e Execução

### Pré-requisitos
- **Erlang/OTP** (versão 24 ou superior). Nenhuma biblioteca externa é necessária.

### Instalação no Linux (Ubuntu/Debian)
```bash
sudo apt update
sudo apt install erlang
```

### Instalação no macOS (Homebrew)
```bash
brew install erlang
```

### Compilação e Execução
Com o arquivo `main.erl` no diretório atual, execute via terminal:

```bash
erlc main.erl
erl -noshell -eval 'main:start(), halt().'
```

Ou através do shell interativo do Erlang:

```erlang
1> c(main).
{ok,main}
2> main:start().
```

---

## 3. Arquitetura da Solução e Distribuição de Tarefas

A solução utiliza o modelo de atores do Erlang com **5 processos concorrentes reais** que não compartilham memória e se comunicam exclusivamente por troca de mensagens assíncronas (`!`) e leitura seletiva bloqueante (`receive`):

| Processo | Função | Responsabilidades |
| :--- | :--- | :--- |
| **Coordenador** | `start/0` | Cria o servidor e os usuários, aguarda a confirmação de registro de todos (`wait_ready/1`), dispara as notificações identificadas, coleta os relatórios finais (`wait_finished/2`), encerra o servidor e audita os totais. |
| **Servidor** | `server/1` | Mantém o estado `Users` (um mapa `#{Id => UPid}`) isolado em seu loop recursivo de cauda. Trata registro, distribuição de notificações aos registrados no momento, cancelamento de registro e encerramento. |
| **Usuários (3x)** | `user/4` | Processos independentes (`u1`, `u2`, `u3`). Solicitam registro, notificam o coordenador quando estão prontos, recebem recursivamente as notificações (`receivenotifications/3`), cancelam o registro e reportam os IDs recebidos. |

### Protocolo de Mensagens

| Mensagem | Origem → Destino | Finalidade |
| :--- | :--- | :--- |
| `{register, Id, UPid}` | Usuário → Servidor | Solicita inclusão no mapa de usuários ativos. |
| `{registered, Id}` | Servidor → Usuário | Confirma que o usuário já está registrado antes de qualquer envio. |
| `{ready, Id}` | Usuário → Coordenador | Sinaliza que o registro foi concluído. |
| `{notify, Nid, Text}` | Coordenador → Servidor | Envia uma nova notificação identificada por `Nid`. |
| `{notification, Nid, Text}` | Servidor → Usuário | Encaminha a notificação a cada usuário registrado no momento. |
| `{unregister, Id, UPid}` | Usuário → Servidor | Solicita remoção da lista de usuários ativos após receber tudo. |
| `{unregistered, Id}` | Servidor → Usuário | Confirma o cancelamento do registro. |
| `{finished, Id, Recebidas}` | Usuário → Coordenador | Entrega a lista de `Nid`s recebidos para auditoria final. |
| `{stop, CoorPid}` / `{stopped, SPid}` | Coordenador ↔ Servidor | Solicita o encerramento do servidor e confirma que ele processou a solicitação; a confirmação é enviada antes de o processo terminar. |

---

## 4. Mecanismos de Comunicação e Sincronização

- **Passagem de Mensagens (`!` e `receive`):** Toda comunicação ocorre via envio assíncrono para caixas de entrada (*mailboxes*) individuais e leitura bloqueante com casamento de padrões (*pattern matching*).
- **Barreiras de Sincronização sem `sleep` e sem Espera Ocupada:**
  - `wait_ready/1`: bloqueia o coordenador em `receive` até que todos os usuários confirmem `{ready, Id}`. Isso garante o **Requisito 1** (todos registrados e confirmados antes do disparo de notificações) sem usar `timer:sleep`.
  - `wait_finished/2`: bloqueia o coordenador até receber `{finished, Id, Recebidas}` de todos os usuários, garantindo independência da ordem de escalonamento dos processos.
- **Estado Imutável e Isolado:** O mapa `Users` pertence exclusivamente ao processo `server/1`, evitando condições de corrida (*race conditions*). Como `maps:values(Users)` contém uma entrada única por `Id` registrado, cada notificação é entregue exatamente uma vez por usuário ativo (**Requisito 2**).

---

## 5. Reunião de Resultados e Coordenação do Encerramento

1. **Reunião de Resultados:** Ao concluir o recebimento das mensagens e o cancelamento de registro, cada usuário envia `{finished, Id, Recebidas}` com a lista de `Nid`s processados. A função `wait_finished/2` consolida essas listas em um mapa `#{Id => Recebidas}`.
2. **Coordenação do Encerramento:** Somente após receber `finished` de todos os usuários, o coordenador envia `{stop, CoorPid}` ao servidor (**Requisito 4**). Cada usuário envia `finished` como última ação da função `user/4`, mas o recebimento dessa mensagem não confirma que o processo do usuário já terminou. O servidor imprime a mensagem de encerramento e responde `{stopped, self()}` antes de sair; portanto, essa confirmação também não garante que o processo servidor já terminou. O código não monitora a saída dos processos.
3. **Auditoria Final:** O coordenador ordena os IDs recebidos por cada usuário (`lists:sort/1`), compara com `[1, 2]` e contabiliza o total global de entregas (`3 usuários × 2 notificações = 6`).

---

## 6. Exemplo de Execução

A ordem de impressão entre `u1`, `u2` e `u3` pode variar conforme o escalonamento da BEAM, mas a verificação final e os totais permanecem determinísticos:

```text
Usuario u1 registrado
Usuario u2 registrado
Usuario u3 registrado
O usuario u1 recebeu [1]: "Nova mensagem"
O usuario u2 recebeu [1]: "Nova mensagem"
O usuario u3 recebeu [1]: "Nova mensagem"
O usuario u1 recebeu [2]: "Última mensagem"
O usuario u2 recebeu [2]: "Última mensagem"
O usuario u3 recebeu [2]: "Última mensagem"
Usuario u1 cancelou o registro
Usuario u2 cancelou o registro
Usuario u3 cancelou o registro
Encerrando 
u1: esperado [1,2], obtido [1,2] -> OK
u2: esperado [1,2], obtido [1,2] -> OK
u3: esperado [1,2], obtido [1,2] -> OK
Total de entregas: esperado 6, obtido 6
```

- **Total esperado:** `6` entregas (`[1, 2]` para cada um dos 3 usuários)
- **Total obtido:** `6` entregas (`OK` para todos os usuários)

---

## 7. Testes Realizados

- **Verificação de Perda e Duplicação:** Cada notificação possui identificador numérico único (`1`, `2`). A auditoria compara `lists:sort(Obtidos)` com `[1, 2]` para cada usuário, detectando imediatamente qualquer ausência (perda) ou repetição (duplicação) de IDs.
- **Independência de Escalonamento:** Execuções sucessivas demonstraram que, mesmo quando os usuários são escalonados em ordens distintas (ex.: `u3` registrando ou recebendo antes de `u1`), a barreira `wait_ready/1` impede envios prematuros e todos os usuários recebem integralmente as mensagens.
- **Exclusividade de Usuários Registrados:** Validou-se que notificações enviadas após um usuário executar `{unregister, Id, UPid}` não são encaminhadas a ele, pois `maps:remove(Id, Users)` remove seu PID do estado do servidor.
- **Término dos Processos:** Uma comparação de `length(erlang:processes())` antes e depois de `main:start()` pode ser usada como verificação observacional. Como o código não monitora a saída dos processos e as mensagens `finished` e `stopped` são enviadas antes do término dos respectivos processos, essa comparação não constitui uma garantia determinística de que todos já terminaram no instante da checagem.

---
