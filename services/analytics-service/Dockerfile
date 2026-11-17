FROM python:3.11-slim

WORKDIR /app

# a imagem base vem com pacotes Debian atrasados e o scan barra por vulnerabilidade critica
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# o processo nao roda como root, exigencia do securityContext do deployment
RUN useradd --create-home --shell /usr/sbin/nologin appuser && chown -R appuser /app
USER appuser

EXPOSE 8005

# o opentelemetry-instrument sobe o SDK e instrumenta flask, requests e o driver do banco antes do app importar
# um worker com threads: o SDK do OTel nao lida bem com varios processos filhos do gunicorn
CMD ["opentelemetry-instrument", "gunicorn", "--bind", "0.0.0.0:8005", "--workers", "1", "--threads", "4", "app:app"]
