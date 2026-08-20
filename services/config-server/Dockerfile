# Expects the jar to already be built: run `mvn -pl services/config-server -am install` (or the
# repo-root `mvn install`) before `docker compose build`. Deliberately not a multi-stage Maven
# build - with 16 services eventually in this repo, rebuilding the whole reactor inside every image
# build is minutes of wasted time per service. CI builds the jar once and feeds it to every image.
FROM eclipse-temurin:17-jre-alpine

RUN addgroup -S delivery && adduser -S delivery -G delivery
USER delivery
WORKDIR /app

COPY --chown=delivery:delivery target/config-server-*.jar app.jar

EXPOSE 8888

# Container-aware heap sizing: the JVM reads the cgroup limit rather than the host's total RAM.
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75 -XX:+UseContainerSupport"

HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=5 \
  CMD wget -qO- http://localhost:8888/actuator/health/readiness | grep -q UP || exit 1

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar app.jar"]
