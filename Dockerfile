FROM golang:alpine AS build

WORKDIR /build

COPY . .

RUN go build -ldflags '-s -w'

FROM alpine:latest

COPY --from=build /build/chat /app/yalk
COPY --from=build /build/static /app/static

WORKDIR /app

# It is adised to use '0.0.0.0' to allow all incoming connections
ENV HOST_ADDR="0.0.0.0"
ENV HTTP_PORT=80
ENV WEB_URL="https://localhost"

ENV SOCKET_PORT=9988
ENV SOCKET_TRANSPORT="tcp"

ENV DB_ADDR="172.17.0.2"
ENV DB_PORT=5432
ENV DB_NAME="db_chat"
ENV DB_USER="postgres"
ENV DB_PASSWORD="changeme"
ENV DB_SSLMODE="disable"

EXPOSE 80 443

CMD ["/app/yalk"]
