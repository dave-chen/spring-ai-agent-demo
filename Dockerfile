FROM gradle:9.2.1-jdk21 AS build
WORKDIR /workspace
COPY --chown=gradle:gradle . /workspace
RUN gradle bootJar --no-daemon

FROM eclipse-temurin:21-jre-jammy
EXPOSE 8080
ARG JAR_FILE=/workspace/build/libs/*.jar
COPY --from=build ${JAR_FILE} /app/app.jar
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
