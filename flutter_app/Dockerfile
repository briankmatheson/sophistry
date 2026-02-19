FROM ghcr.io/cirruslabs/flutter:stable AS build
ARG APP_VERSION=dev
WORKDIR /app
COPY  . .

RUN flutter pub get && \
    flutter build web --dart-define=BACKEND_BASE_URL=https://app.sophistry.online --dart-define=APP_VERSION=${APP_VERSION}

FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
