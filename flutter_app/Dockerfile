FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app
COPY  . .

RUN flutter pub get && \
    flutter build web --dart-define=BACKEND_BASE_URL=https://app.sophistry.online

FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
