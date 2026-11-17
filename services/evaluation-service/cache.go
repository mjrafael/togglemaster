package main

import (
	"context"
	"time"

	"github.com/go-redis/redis/v8"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

// o go-redis v8 só tem instrumentação oficial presa a uma versão antiga do OpenTelemetry,
// então o span de cliente é criado aqui. db.system e peer.service fazem o Redis aparecer
// como dependência no Service Map do APM
func (a *App) spanRedis(ctx context.Context, operacao string) (context.Context, trace.Span) {
	return tracer.Start(ctx, "redis "+operacao,
		trace.WithSpanKind(trace.SpanKindClient),
		trace.WithAttributes(
			attribute.String("db.system", "redis"),
			attribute.String("db.operation", operacao),
			attribute.String("peer.service", "redis"),
			attribute.String("server.address", a.RedisAddr),
		),
	)
}

func (a *App) redisGet(ctx context.Context, chave string) (string, error) {
	ctx, span := a.spanRedis(ctx, "GET")
	defer span.End()

	val, err := a.RedisClient.Get(ctx, chave).Result()
	switch {
	case err == redis.Nil:
		// chave ausente é cache miss, não erro
		span.SetAttributes(attribute.Bool("cache.hit", false))
	case err != nil:
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
	default:
		span.SetAttributes(attribute.Bool("cache.hit", true))
	}
	return val, err
}

func (a *App) redisSet(ctx context.Context, chave string, valor []byte, ttl time.Duration) {
	ctx, span := a.spanRedis(ctx, "SET")
	defer span.End()

	if err := a.RedisClient.Set(ctx, chave, valor, ttl).Err(); err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
	}
}
