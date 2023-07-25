FROM cloudron/base:4.0.0@sha256:31b195ed0662bdb06a6e8a5ddbedb6f191ce92e8bee04c03fb02dd4e9d0286df

ENV KC_VERSION=22.0.1

RUN mkdir -p /app/code /app/data && \
    apt-get update && \
    apt-get install -y openjdk-19-jre-headless && apt-get clean && apt-get autoremove && \
    rm -rf /var/cache/apt /var/lib/apt/lists

RUN curl -L https://github.com/keycloak/keycloak/releases/download/$KC_VERSION/keycloak-$KC_VERSION.tar.gz | \
    tar zx --strip-components 1 -C /app/code

RUN /app/code/bin/kc.sh build \
    --metrics-enabled=false \
    --db=postgres \
    --features='authorization,account2,account-api,impersonation,client-policies' \
    --features-disabled='token-exchange,web-authn,ciba,par'

RUN mv /app/code/providers /app/code/providers-orig && ln -sf /app/data/providers /app/code/providers && \
    mv /app/code/themes /app/code/themes-orig && ln -sf /app/data/themes /app/code/themes && \
    mv /app/code/conf /app/code/conf-orig && ln -sf /app/data/conf /app/code/conf && \
    mkdir -p /app/code/data && ln -sf /app/data/tmp /app/code/data/tmp && \
    chown cloudron:cloudron /app/data && \
    rm /app/code/conf-orig/keycloak.conf && \
    rm /app/code/conf-orig/cache-ispn.xml

ADD start.sh first_run.sh /app/code/

CMD [ "/app/code/start.sh" ]