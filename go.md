# Assunto 1 – Concorrência com Go

**Questão escolhida:** Questão 1 – Processamento de pedidos em uma loja virtual.

Arquivo: `main.go` (um único arquivo, apenas biblioteca padrão do Go).

## 1. Instalação, compilação e execução

Não há dependências externas. É necessário apenas o Go (versão 1.18 ou superior).

```bash
# instalar o Go (Ubuntu/Debian)
sudo apt install golang-go      # ou baixar em https://go.dev/dl/

# executar
go run main.go

# ou compilar e executar o binário
go build -o pedidos main.go
./pedidos

# executar com o detector de condições de corrida
go run -race main.go
```

## 2. Arquitetura e distribuição das tarefas

```
main ──(canal tasks)──► worker 0 ──┐
     ──(canal tasks)──► worker 1 ──┼──(canal processed_tasks)──► coord ──(canal done)──► main
     ──(canal tasks)──► worker 2 ──┘
```

- **main:** gera 20 pedidos com IDs sequenciais de 0 a 19 e quantidade e valor unitário aleatórios, dispara as goroutines e envia os pedidos para o canal `tasks`.
- **3 workers (goroutines):** cada um lê pedidos do canal `tasks`, simula um tempo de processamento aleatório (0 a 24 ms), valida o pedido, calcula o valor total e envia o resultado (`processed_order`, que carrega o `id` do pedido) ao canal `processed_tasks`.
- **coord (goroutine coordenadora):** lê o canal `processed_tasks` e contabiliza pedidos válidos, inválidos e a soma dos valores dos válidos.

**Distribuição:** os três workers leem do mesmo canal `tasks`. O Go garante que cada valor enviado a um canal é recebido por **uma única** goroutine, então cada pedido é processado exatamente uma vez, e o worker que estiver livre pega o próximo pedido.

**Regra de validade:** o pedido é válido se `quantidade > 0` e `valor unitário >= 0`. Pedido inválido tem valor total 0 e não entra na soma.

## 3. Comunicação e sincronização

| Mecanismo | Uso |
|---|---|
| `tasks` (`chan order`, buffer 20) | main → workers: distribuição dos pedidos |
| `processed_tasks` (`chan processed_order`, buffer 20) | workers → coord: envio dos resultados, com o `id` do pedido |
| `done` (`chan bool`, sem buffer) | coord → main: sinal de que o resumo final foi impresso |
| `sync.WaitGroup` (`wg`) | a main espera os 3 workers terminarem |

Os contadores e o total pertencem somente à goroutine `coord`, e a comunicação entre goroutines é feita só por canais. Por isso não é necessário `Mutex`.

## 4. Reunião dos resultados e encerramento

O encerramento segue esta ordem na `main`:

1. `close(tasks)`: avisa que não há mais pedidos. Cada worker sai do `for range` ao terminar os pedidos que já estavam no canal, e o `defer wg.Done()` é executado na saída.
2. `wg.Wait()`: espera os 3 workers saírem. Como cada worker envia o resultado antes de ler o próximo pedido, ao fim do `Wait` todos os resultados já estão no canal `processed_tasks`.
3. `close(processed_tasks)`: avisa o `coord` que não virão mais resultados. Ele esvazia o canal, sai do `for range`, imprime o resumo final e envia `true` em `done`.
4. `<-done`: a `main` só termina depois de receber esse sinal, garantindo que o resumo foi impresso.

Fechar `processed_tasks` somente depois do `wg.Wait()` é o que evita perda de resultados (fechar antes poderia causar `panic` ao enviar em canal fechado).

## 5. Exemplo de execução e totais

O resumo final impresso pelo `coord` tem este formato (os valores mudam a cada execução, porque os pedidos são aleatórios):

```
Processados:  20  Válidos:  17  Inválidos 3  Valor Total do Pedido: <total>
```

**Totais esperados:**
- Processados = 20 (quantidade de pedidos gerados).
- Válidos + Inválidos = 20.
- Inválidos = número de pedidos com quantidade ≤ 0 (ou valor negativo) no log.
- Valor total = soma de `quantidade × preço` dos pedidos válidos listados no log.

**Totais obtidos:** os valores do resumo final impresso pelo programa.

> Cole aqui a saída real da sua execução e a conferência manual do total.

A ordem das mensagens intermediárias muda a cada execução, o que é esperado: os workers terminam em tempos diferentes, e o resultado final não depende dessa ordem.

## 6. Testes realizados

- **Perda:** o resumo final deve mostrar 20 processados. Também é possível contar as linhas de entrada: `go run main.go | grep -c "chegou no worker"` deve retornar 20.
- **Duplicação:** nenhum id deve aparecer duas vezes: `go run main.go | grep "chegou no worker" | awk '{print $2}' | sort -n | uniq -d` não deve imprimir nada.
- **Correção da validação e do total:** conferência manual dos pedidos com quantidade ≤ 0 (inválidos) e da soma de quantidade × preço dos válidos.
- **Término correto:** execuções repetidas sem *deadlock* e sem `panic`, por exemplo `for i in $(seq 1 50); do go run main.go | tail -1; done`.
- **Condições de corrida:** execução com `go run -race main.go`, sem avisos.