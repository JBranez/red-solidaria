# Build de Angular 22.
FROM node:22.22.3-bookworm-slim AS build
WORKDIR /app
COPY frontend/package.json frontend/package-lock.json ./
# El hook postinstall genera el tema y necesita este script antes de npm ci.
COPY frontend/scripts/ ./scripts/
RUN npm ci
COPY frontend/ ./
RUN npm run build

# Solo sirve los recursos estáticos; Caddy gestiona TLS y el proxy a FastAPI.
FROM nginx:1.29-alpine AS runtime
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist/frontend/browser /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1/ || exit 1
