package main

import (
	"encoding/json"
	"log"
	"net/http"
	"sync/atomic"
)

// modoFalha reproduz a falha silenciosa do enunciado: o processo continua vivo e o /health
// responde 200, então a liveness probe não percebe nada, mas as rotas de negócio devolvem 500.
// o estado vive só na memória do processo, por isso um rollout restart limpa a falha
var modoFalha atomic.Bool

func (a *App) falhaHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
		modoFalha.Store(true)
		log.Println("MODO DE FALHA LIGADO: rotas de negócio passam a responder 500")
	case http.MethodDelete:
		modoFalha.Store(false)
		log.Println("modo de falha desligado")
	default:
		http.Error(w, "Método não permitido", http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"modo_falha": modoFalha.Load()})
}

func middlewareFalha(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if modoFalha.Load() && r.URL.Path != "/health" && r.URL.Path != "/admin/falha" {
			log.Printf("modo de falha ativo, respondendo 500 em %s", r.URL.Path)
			http.Error(w, "falha simulada", http.StatusInternalServerError)
			return
		}
		next.ServeHTTP(w, r)
	})
}
