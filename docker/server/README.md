# Servidor oficial do Speedoru

```
jogador ──UDP 7350──> speedoru.padoru.org (VM "speedoru", São Paulo) ──> server ──rede do Compose──> libsql
```

| | |
|---|---|
| Projeto GCP | `gen-lang-client-0425635607` |
| VM | `speedoru`, `southamerica-east1-a`, e2-small, Ubuntu 26.04 mínimo |
| IP fixo | `speedoru-ip` (35.215.209.73, nível Standard) |
| DNS | registro A `speedoru.padoru.org` na zona `padoru-org` |
| Firewall | regra `speedoru-server` (UDP 7350, tag `speedoru-server`) |
| Imagem | `southamerica-east1-docker.pkg.dev/gen-lang-client-0425635607/speedoru/server` |
| Compose | `/srv/speedoru/compose.yml` (este diretório) |

O jogo conecta em `speedoru.padoru.org:7350` por padrão (`NetProtocol.DEFAULT_HOST`).

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
