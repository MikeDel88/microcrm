FROM node:20-alpine AS front-build
WORKDIR /src

COPY ./front/package*.json /src/

RUN npm ci

COPY ./front /src

RUN npm run build

FROM gradle:8.7.0-jdk17-alpine AS back-build

WORKDIR /src

COPY ./back/gradlew ./back/build.gradle ./back/settings.gradle /src/
COPY ./back/gradle /src/gradle

RUN ./gradlew --no-daemon dependencies > /dev/null

COPY ./back /src

RUN ./gradlew --no-daemon bootJar -x test

FROM caddy:2.11.7-alpine AS front

COPY --from=front-build /src/dist/microcrm/browser /app/front
COPY misc/docker/Caddyfile /app/Caddyfile

WORKDIR /app

RUN adduser -D app
USER app

EXPOSE 80
EXPOSE 443

CMD ["caddy", "run", "--config", "/app/Caddyfile"]

FROM eclipse-temurin:17-jre-alpine AS back

COPY --from=back-build /src/build/libs/microcrm.jar /app/back/microcrm.jar

RUN adduser -D app
USER app

WORKDIR /app

EXPOSE 8080

CMD ["java", "-jar", "/app/back/microcrm.jar"]



