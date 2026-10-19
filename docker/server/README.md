# Servidor oficial do Speedoru

```
jogador ──UDP 7350──> play.speedoru.padoru.org (VM "speedoru", São Paulo) ──> server ──rede do Compose──> libsql
```

| | |
|---|---|
| Projeto GCP | `gen-lang-client-0425635607` |
| VM | `speedoru`, `southamerica-east1-a`, e2-standard-2, Ubuntu 26.04 mínimo |
| IP | efêmero (nível Standard): muda a cada vez que a VM liga |
| DNS | registro A `play.speedoru.padoru.org` na zona `padoru-org` (TTL 60), atualizado pela VM a cada boot |
| Firewall | regra `speedoru-server` (UDP 7350, tag `speedoru-server`) |
| Imagem | `southamerica-east1-docker.pkg.dev/gen-lang-client-0425635607/speedoru/server` |
| Compose | `/srv/speedoru/compose.yml` (este diretório) |

O jogo conecta em `play.speedoru.padoru.org:7350` por padrão (`NetProtocol.DEFAULT_HOST`). Até a
0.12.0 o endereço era `speedoru.padoru.org`, que agora é o site do jogo (VM de Iowa, nginx de borda
em `/srv/edge` e arquivos em `/srv/speedoru-site`); o cliente troca o endereço antigo salvo no
aparelho pelo novo (`NetProtocol.OLD_HOSTS`).

A VM não tem IP fixo. O `startup-script` dos metadados dela pega o IP externo atual e regrava o
registro A pela API do Cloud DNS, com o token do servidor de metadados (a VM tem o escopo
`ndev.clouddns.readwrite`). Os registros ficam no log do sistema com a tag `speedoru-dns`
(`sudo journalctl -t speedoru-dns`).

## Publicar uma versão do servidor

O servidor e o cliente precisam falar a mesma versão do protocolo (`NetProtocol.VERSION`), então
publique o servidor a partir do mesmo commit da release do jogo. A imagem é construída a partir do
commit, não da pasta de trabalho:

```bash
git archive --format=tar HEAD | docker build -f docker/server/Dockerfile \
  -t southamerica-east1-docker.pkg.dev/gen-lang-client-0425635607/speedoru/server:latest -
docker push southamerica-east1-docker.pkg.dev/gen-lang-client-0425635607/speedoru/server:latest
```

Na VM:

```bash
gcloud compute ssh speedoru --zone southamerica-east1-a
cd /srv/speedoru && sudo docker compose pull && sudo docker compose up -d
sudo docker compose logs -f server
```

## Banco

O Compose sobe o `libsql-server` (o servidor do Turso) sem porta publicada: só o servidor do jogo o
alcança. Os dados ficam no volume `speedoru_db-data`, e as skins enviadas pelos jogadores no
`speedoru_server-data`. Para usar o Turso na nuvem, veja o comentário no `compose.yml`.
