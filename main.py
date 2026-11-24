import multiprocessing
import socket
import time
import random
from pylinda import server, client, Any

HOST = "127.0.0.1"
PORT = 21643


def conectar():
    for _ in range(30):
        try:
            c = client()
            c.attach(HOST, PORT)
            return c
        except ConnectionRefusedError:
            time.sleep(0.05)


def trabalhador(nome):
    ts = conectar()
    while True:
        _, id_chamado, categoria, desc = ts.in_b(("chamado", Any(int), Any(str), Any(str)))

        if id_chamado == -1:
            print(f"[{nome}] Encerrando.")
            break

        _, _, sla = ts.rd_b(("config", categoria, Any(str)))
        print(f"[{nome}] Chamado #{id_chamado:02d} ({categoria}) -> {sla} | {desc}")

        time.sleep(random.uniform(0.05, 0.15))

        ts.post(("resolucao", id_chamado, nome, sla))
    ts.sock.close()


def main():
    srv = multiprocessing.Process(target=server, kwargs={"PORT": PORT}, daemon=True)
    srv.start()

    ts = conectar()

    ts.post(("config", "critica", "Prioridade Alta - 1h"))
    ts.post(("config", "media",   "Prioridade Normal - 4h"))
    ts.post(("config", "baixa",   "Prioridade Baixa - 24h"))

    chamados = [
        (1, "critica", "Servidor fora do ar"),
        (2, "baixa",   "Troca de mouse"),
        (3, "media",   "Lentidão no sistema"),
        (4, "critica", "Falha no login"),
        (5, "baixa",   "Acesso à pasta"),
        (6, "media",   "Erro no relatório"),
        (7, "critica", "Banco sem conexões"),
        (8, "baixa",   "Assinatura de e-mail"),
        (9, "media",   "Impressora offline"),
        (10, "critica", "SSL expirado"),
        (11, "baixa",   "Dúvida no formulário"),
        (12, "media",   "VPN caindo"),
        (13, "critica", "Gateway de pagamento"),
        (14, "baixa",   "Instalar leitor PDF"),
        (15, "media",   "Agenda travada"),
    ]
    for cid, cat, desc in chamados:
        ts.post(("chamado", cid, cat, desc))

    atendentes = ["Atendente-1", "Atendente-2", "Atendente-3"]
    workers = [multiprocessing.Process(target=trabalhador, args=(a,)) for a in atendentes]
    for w in workers:
        w.start()

    resolvidos = {}
    for _ in range(len(chamados)):
        _, cid, atendente, sla = ts.in_b(("resolucao", Any(int), Any(str), Any(str)))
        resolvidos[cid] = (atendente, sla)

    for _ in workers:
        ts.post(("chamado", -1, "FIM", "ENCERRAR"))

    for w in workers:
        w.join()

    pendentes = sorted(set(range(1, 16)) - set(resolvidos.keys()))
    print("\n--- RESUMO FINAL ---")
    for cid in sorted(resolvidos.keys()):
        atendente, sla = resolvidos[cid]
        print(f"Chamado #{cid:02d}: resolvido por {atendente} ({sla})")
    print(f"\nEsperado: 15 | Resolvido: {len(resolvidos)} | Pendentes: {pendentes}")

    ts.reply(None, "shutdown")
    ts.sock.close()
    try:
        with socket.create_connection((HOST, PORT), timeout=1):
            pass
    except OSError:
        pass
    srv.join(timeout=2)


if __name__ == "__main__":
    main()