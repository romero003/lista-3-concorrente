# Lista de Exercícios 3 — Programação Concorrente (Python + Linda)

**Aluno:** João Victor Nascimento Lima  
**Assunto:** Coordenação com Linda em Python  
**Questão Escolhida:** Questão 7 – Fila compartilhada de chamados de suporte

---

## 1. Situação-Problema

Uma equipe de suporte recebe chamados de usuários que ficam disponíveis em um quadro compartilhado (**Espaço de Tuplas**). Os atendentes (processos trabalhadores) retiram os chamados que conseguem assumir, consultam uma regra persistente de prioridade/prazo para a categoria do chamado e publicam a resolução para que o coordenador acompanhe e valide o serviço.

---

## 2. Biblioteca Utilizada, Instalação e Execução

### Biblioteca e Versão
- **Linguagem:** Python 3
- **Biblioteca Linda:** `pylinda` — **versão `0.1.4`**
- **Dependência auxiliar:** `multiprocessing` (biblioteca padrão do Python para criação de processos reais).

### Correspondência entre Primitivas Linda e a API do `pylinda`

| Primitiva Linda | Chamada no `pylinda` | Semântica / Comportamento |
| :--- | :--- | :--- |
| **`out(tupla)`** | `ts.post(tupla)` | Publica uma tupla no espaço compartilhado de forma não bloqueante. |
| **`in(template)`** | `ts.in_b(template)` | **Retirada bloqueante (`IN_B`):** aguarda até existir uma tupla compatível, **remove-a** atomicamente do espaço e a retorna. |
| **`rd(template)`** | `ts.rd_b(template)` | **Leitura bloqueante (`RD_B`):** aguarda até existir uma tupla compatível e a retorna **sem removê-la** do espaço. |
| *Curingas de tipo* | `Any(int)`, `Any(str)` | Objetos de casamento de padrões (*pattern matching*) importados de `pylinda` para filtrar tuplas por tipo. |

### Instruções de Instalação e Execução (Linux)

1. Crie e ative um ambiente virtual Python:
```bash
python3 -m venv .venv
source .venv/bin/activate
```

2. Instale a biblioteca `pylinda`:
```bash
pip install pylinda==0.1.4
```

3. Execute o programa (`main.py`):
```bash
python3 main.py
```

---

## 3. Arquitetura da Solução e Distribuição de Tarefas

A aplicação utiliza o modelo de coordenação por espaço de tuplas do `pylinda` sobre comunicação TCP local (`127.0.0.1:21643`), com **5 processos concorrentes reais** criados via `multiprocessing.Process`:

| Processo | Função | Responsabilidades |
| :--- | :--- | :--- |
| **Servidor Linda** | `pylinda.server` | Processo em segundo plano que hospeda e gerencia o espaço de tuplas compartilhado e as filas de bloqueio (`POST` e `BLOCK`). |
| **Coordenador** | `main()` | Publica as configurações de SLA/prioridade, insere os **15 chamados** no espaço, coleta as **15 resoluções**, emite as tuplas de término e audita possíveis pendências. |
| **Trabalhadores (3x)** | `trabalhador(nome)` | Três processos independentes (`Atendente-1`, `Atendente-2`, `Atendente-3`). Retiram chamados disponíveis, consultam o prazo da categoria sem remover a configuração e publicam as resoluções. |

### Estrutura das Tuplas no Espaço Compartilhado

1. **Configurações persistentes (lidas via `rd_b`):**
   - `("config", "critica", "Prioridade Alta - 1h")`
   - `("config", "media", "Prioridade Normal - 4h")`
   - `("config", "baixa", "Prioridade Baixa - 24h")`
2. **Chamados de suporte (retirados via `in_b`):**
   - `("chamado", id_chamado, categoria, descricao)` — identificadores de `1` a `15`.
3. **Tupla de término compatível (retirada via `in_b`):**
   - `("chamado", -1, "FIM", "ENCERRAR")` — mesma aridade e tipos da tupla de chamado (`("chamado", Any(int), Any(str), Any(str))`), permitindo encerramento bloqueante sem espera ocupada.
4. **Resoluções publicadas (escritas via `post` e coletadas via `in_b`):**
   - `("resolucao", id_chamado, nome_atendente, sla)`

---

## 4. Mecanismos de Comunicação e Sincronização

- **Coordenação Exclusiva pelo Espaço de Tuplas:** Não foram utilizadas filas (`Queue`), dicionários compartilhados (`Manager.dict`) ou troca direta de mensagens entre processos. Toda a interação ocorre exclusivamente via `post`, `in_b` e `rd_b`.
- **Exclusividade na Retirada de Tarefas (Requisito 1):** Como `ts.in_b(...)` remove atomicamente a tupla do servidor Linda no momento da leitura, cada chamado é assumido e processado por **exatamente um** trabalhador.
- **Persistência de Configurações (Requisito 2):** O uso de `ts.rd_b(("config", categoria, Any(str)))` consulta a prioridade/prazo mantendo a tupla intacta no espaço para os demais atendentes.
- **Ausência de Espera Ocupada (Requisito 5 e Regra Geral 3):** As operações `in_b` e `rd_b` bloqueiam o socket do cliente até que o servidor `pylinda` notifique a chegada de uma tupla compatível. O `time.sleep(random.uniform(0.05, 0.15))` é empregado apenas dentro de `trabalhador` para simular o tempo de análise técnica de cada chamado (permitido pela Regra Geral 4).

---

## 5. Reunião de Resultados e Coordenação do Encerramento

1. **Reunião de Resultados (Requisito 3):** O coordenador executa exatamente 15 chamadas bloqueantes `ts.in_b(("resolucao", Any(int), Any(str), Any(str)))`, armazenando cada resolução pelo seu `cid`. Ao final, compara o conjunto `range(1, 16)` com as chaves obtidas (`set(resolvidos.keys())`) para listar eventuais chamados pendentes.
2. **Coordenação do Encerramento (Requisitos 4 e 5):** Somente após recolher todas as **15 resoluções**, o coordenador publica 3 tuplas `("chamado", -1, "FIM", "ENCERRAR")` (uma por trabalhador). Cada atendente consome uma tupla de término, encerra seu laço e fecha seu socket. Em seguida, o coordenador aguarda `w.join()` de todos os trabalhadores e envia o comando `"shutdown"` para finalizar o processo servidor do `pylinda`.

---

## 6. Exemplo de Execução

*(A distribuição dos chamados entre `Atendente-1`, `Atendente-2` e `Atendente-3` varia conforme o escalonamento do sistema operacional, mas todos os 15 chamados são sempre resolvidos sem pendências).*

```text
[Atendente-1] Chamado #01 (critica) -> Prioridade Alta - 1h | Servidor fora do ar
[Atendente-2] Chamado #02 (baixa) -> Prioridade Baixa - 24h | Troca de mouse
[Atendente-3] Chamado #03 (media) -> Prioridade Normal - 4h | Lentidão no sistema
[Atendente-3] Chamado #04 (critica) -> Prioridade Alta - 1h | Falha no login
[Atendente-1] Chamado #05 (baixa) -> Prioridade Baixa - 24h | Acesso à pasta
[Atendente-2] Chamado #06 (media) -> Prioridade Normal - 4h | Erro no relatório
[Atendente-3] Chamado #07 (critica) -> Prioridade Alta - 1h | Banco sem conexões
[Atendente-1] Chamado #08 (baixa) -> Prioridade Baixa - 24h | Assinatura de e-mail
[Atendente-2] Chamado #09 (media) -> Prioridade Normal - 4h | Impressora offline
[Atendente-3] Chamado #10 (critica) -> Prioridade Alta - 1h | SSL expirado
[Atendente-1] Chamado #11 (baixa) -> Prioridade Baixa - 24h | Dúvida no formulário
[Atendente-2] Chamado #12 (media) -> Prioridade Normal - 4h | VPN caindo
[Atendente-1] Chamado #13 (critica) -> Prioridade Alta - 1h | Gateway de pagamento
[Atendente-3] Chamado #14 (baixa) -> Prioridade Baixa - 24h | Instalar leitor PDF
[Atendente-2] Chamado #15 (media) -> Prioridade Normal - 4h | Agenda travada
[Atendente-1] Encerrando.
[Atendente-3] Encerrando.
[Atendente-2] Encerrando.

--- RESUMO FINAL ---
Chamado #01: resolvido por Atendente-1 (Prioridade Alta - 1h)
Chamado #02: resolvido por Atendente-2 (Prioridade Baixa - 24h)
Chamado #03: resolvido por Atendente-3 (Prioridade Normal - 4h)
Chamado #04: resolvido por Atendente-3 (Prioridade Alta - 1h)
Chamado #05: resolvido por Atendente-1 (Prioridade Baixa - 24h)
Chamado #06: resolvido por Atendente-2 (Prioridade Normal - 4h)
Chamado #07: resolvido por Atendente-3 (Prioridade Alta - 1h)
Chamado #08: resolvido por Atendente-1 (Prioridade Baixa - 24h)
Chamado #09: resolvido por Atendente-2 (Prioridade Normal - 4h)
Chamado #10: resolvido por Atendente-3 (Prioridade Alta - 1h)
Chamado #11: resolvido por Atendente-1 (Prioridade Baixa - 24h)
Chamado #12: resolvido por Atendente-2 (Prioridade Normal - 4h)
Chamado #13: resolvido por Atendente-1 (Prioridade Alta - 1h)
Chamado #14: resolvido por Atendente-3 (Prioridade Baixa - 24h)
Chamado #15: resolvido por Atendente-2 (Prioridade Normal - 4h)

Esperado: 15 | Resolvido: 15 | Pendentes: []
```

- **Total esperado:** `15` chamados resolvidos
- **Total obtido:** `15` chamados resolvidos (`Pendentes: []`)

---

## 7. Testes Realizados

- **Verificação de Perda e Duplicação:** A auditoria final compara o conjunto esperado `{1..15}` com os IDs coletados nas tuplas `"resolucao"`. Em todas as execuções, `len(resolvidos) == 15` e `pendentes == []`, confirmando que nenhum chamado foi perdido ou atendido em duplicidade.
- **Persistência das Tuplas de Configuração (`rd_b`):** Verificou-se que os três trabalhadores consultaram repetidamente as categorias `"critica"`, `"media"` e `"baixa"` ao longo de todos os 15 chamados sem que nenhuma tupla `"config"` fosse consumida do espaço.
- **Independência de Escalonamento:** Variando os atrasos aleatórios (`random.uniform`) entre os trabalhadores, comprovou-se que trabalhadores mais rápidos assumem mais chamados dinamicamente sem alterar o resultado final.
- **Término Correto dos Processos:** Confirmou-se que todos os trabalhadores recebem exatamente uma tupla de encerramento após a 15ª resolução e finalizam via `w.join()`, seguidos pelo desligamento do servidor `pylinda` (`srv.join()`), sem deixar processos órfãos no sistema operacional.

---

