FROM golang:1.25-alpine AS build

WORKDIR /src
COPY go.mod go.su[m] ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/app .

# distroless nao tem shell nem gerenciador de pacotes, o que reduz o que o scan de imagem encontra
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/app /app
USER nonroot:nonroot
EXPOSE 8004

ENTRYPOINT ["/app"]
