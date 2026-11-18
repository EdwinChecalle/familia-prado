# Imagen multi-arquitectura: AMD64 para Render y ARM64 para Oracle Ampere A1.
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml ./
COPY src ./src
RUN mvn -B -DskipTests package

FROM eclipse-temurin:21-jre
RUN groupadd --system prado && useradd --system --gid prado --home /app prado
WORKDIR /app
COPY --from=build /workspace/target/*.jar /app/app.jar
USER prado
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=65 -Dfile.encoding=UTF-8"
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
