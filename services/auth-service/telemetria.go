package main

import (
	"context"
	"log"
	"os"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

// iniciarTelemetria liga o envio de traces para o OTel Collector.
// endpoint, nome do serviço e atributos vêm das variáveis OTEL_* do deployment,
// então o mesmo binário roda local sem collector nenhum
func iniciarTelemetria(ctx context.Context) func(context.Context) error {
	if os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT") == "" {
		log.Println("OTEL_EXPORTER_OTLP_ENDPOINT não definida, seguindo sem telemetria")
		return func(context.Context) error { return nil }
	}

	exportador, err := otlptracehttp.New(ctx)
	if err != nil {
		log.Printf("não foi possível criar o exportador OTLP, seguindo sem telemetria: %v", err)
		return func(context.Context) error { return nil }
	}

	recurso, err := resource.New(ctx, resource.WithFromEnv(), resource.WithTelemetrySDK())
	if err != nil {
		log.Printf("atributos de recurso incompletos: %v", err)
	}

	provedor := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exportador),
		sdktrace.WithResource(recurso),
	)
	otel.SetTracerProvider(provedor)

	// traceparent é o cabeçalho que liga os spans de serviços diferentes no mesmo trace
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	log.Println("telemetria ligada, enviando traces para o OTel Collector")
	return provedor.Shutdown
}
