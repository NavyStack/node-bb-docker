FROM node:lts AS git

ENV TZ="Asia/Seoul"

WORKDIR /usr/src/app/

RUN apt-get update \
  && apt-get -y --no-install-recommends install tini

RUN git clone --recurse-submodules -j8 --depth 1 https://github.com/NodeBB/NodeBB.git .

RUN find . -mindepth 1 -maxdepth 1 -name '.*' ! -name '.' ! -name '..' -exec bash -c 'echo "Deleting {}"; rm -rf {}' \; \
  && rm -rf install/docker/entrypoint.sh \
  && rm -rf docker-compose.yml \
  && rm -rf Dockerfile
  ## && sed -i 's|"\*/jquery":|"jquery":|g' install/package.json

FROM node:lts AS node_modules_touch

ENV NODE_ENV=production \
    TZ="Asia/Seoul"

WORKDIR /usr/src/app/

COPY --from=git /usr/src/app/install/package.json /usr/src/app/

RUN --mount=type=cache,id=pnpm,target=/pnpm/store \
  npm install \
    @nodebb/nodebb-plugin-reactions \
    nodebb-plugin-adsense \
    nodebb-plugin-extended-markdown \
    nodebb-plugin-meilisearch \
    nodebb-plugin-question-and-answer \
    nodebb-plugin-sso-github \
    ## nodebb-plugin-knowledge-base \
  && npm install --package-lock-only --omit=dev
  ## pnpm import \
  ## && pnpm install --prod --frozen-lockfile
  
FROM node:lts-slim AS final

ENV NODE_ENV=production \
  NPM_CONFIG_UPDATE_NOTIFIER="false" \
  DAEMON=false \
  SILENT=false \
  USER=nodebb \
  UID=1001 \
  GID=1001 \
  TZ="Asia/Seoul"

WORKDIR /usr/src/app/

RUN groupadd --gid ${GID} ${USER} \
  && useradd --uid ${UID} --gid ${GID} --home-dir /usr/src/app/ --shell /bin/bash ${USER} \
  && mkdir -p /usr/src/app/logs/ /opt/config/ \
  && chown -R ${USER}:${USER} /usr/src/app/ /opt/config/
  
ENV GOSU_VERSION 1.17
RUN set -eux; \
# save list of currently installed packages for later so we can clean up
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends ca-certificates gnupg wget; \
	rm -rf /var/lib/apt/lists/*; \
	\
	dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
	wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
	wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
	\
# verify the signature
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	\
# clean up fetch dependencies
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	\
	chmod +x /usr/local/bin/gosu; \
# verify that the binary works
	gosu --version; \
	gosu nobody true

COPY --from=node_modules_touch /usr/src/app/ /usr/src/app/
COPY --from=git /usr/src/app/ /usr/src/app/
COPY --from=git /usr/src/app/install/docker/setup.json /usr/src/app/setup.json
COPY --from=git /usr/bin/tini /usr/bin/tini
COPY start.sh start.sh /usr/local/bin/

EXPOSE 4567

VOLUME ["/usr/src/app/node_modules", "/usr/src/app/build", "/usr/src/app/public/uploads", "/opt/config/"]

ENTRYPOINT ["tini", "--", "start.sh"]