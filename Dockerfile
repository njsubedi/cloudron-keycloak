FROM cloudron/base:3.2.0@sha256:ba1d566164a67c266782545ea9809dc611c4152e27686fd14060332dd88263ea

RUN mkdir -p /app/code /app/data && \
    apt-get update && \
    apt-get install -y openjdk-11-jre-headless && apt-get clean && apt-get autoremove && \
    rm -rf /var/cache/apt /var/lib/apt/lists

RUN curl -L https://github.com/keycloak/keycloak/releases/download/17.0.1/keycloak-17.0.1.tar.gz | \
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