# Servidor dedicado do Speedoru (Godot sem janela, ENet/UDP 7350).
#
# Construa a partir da raiz do repositório:
#   docker build -f docker/server/Dockerfile -t speedoru-server .
#
# O banco vem de TURSO_DATABASE_URL / TURSO_AUTH_TOKEN (veja docker/server/compose.yml).

ARG GODOT_TAG=4.7-stable

# --- Godot para Linux -------------------------------------------------------
FROM debian:bookworm-slim AS godot
ARG GODOT_TAG
RUN apt-get update -q \
 && apt-get install -y -q --no-install-recommends ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*
RUN curl -sSfL -o /tmp/godot.zip \
      "https://github.com/godotengine/godot/releases/download/${GODOT_TAG}/Godot_v${GODOT_TAG}_linux.x86_64.zip" \
 && unzip -q /tmp/godot.zip -d /tmp \
 && mv "/tmp/Godot_v${GODOT_TAG}_linux.x86_64" /usr/local/bin/godot \
 && chmod +x /usr/local/bin/godot \
 && rm /tmp/godot.zip

# --- importa os recursos (cria o .godot/) -----------------------------------
FROM godot AS import
WORKDIR /app
COPY . .
RUN godot --headless --path . --import

# --- imagem final -----------------------------------------------------------
FROM debian:bookworm-slim
RUN apt-get update -q \
 && apt-get install -y -q --no-install-recommends ca-certificates libfontconfig1 \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 1000 godot
COPY --from=godot /usr/local/bin/godot /usr/local/bin/godot
COPY --from=import --chown=godot:godot /app /app
USER godot
# skins enviadas pelos jogadores ficam em user://server_skins
VOLUME /home/godot/.local/share/godot/app_userdata/Speedoru
EXPOSE 7350/udp
ENTRYPOINT ["godot", "--headless", "--path", "/app", "--", "--server"]
CMD ["--port=7350"]
