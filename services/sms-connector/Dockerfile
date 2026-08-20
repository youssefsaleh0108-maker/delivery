# See services/config-server/Dockerfile for why this is not a multi-stage Maven build.
FROM eclipse-temurin:17-jre-alpine

RUN addgroup -S delivery && adduser -S delivery -G delivery
USER delivery
WORKDIR /app

COPY --chown=delivery:delivery target/sms-connector-*.jar app.jar

EXPOSE 8112

ENV JAVA_OPTS="-XX:MaxRAMPercentage=75 -XX:+UseContainerSupport"

HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=5 \
  CMD wget -qO- http://localhost:8112/actuator/health/readiness | grep -q UP || exit 1

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar app.jar"]
