FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# o processo nao roda como root, exigencia do securityContext do deployment
RUN useradd --create-home --shell /usr/sbin/nologin appuser && chown -R appuser /app
USER appuser

EXPOSE 8002

CMD ["gunicorn", "--bind", "0.0.0.0:8002", "--workers", "2", "app:app"]
