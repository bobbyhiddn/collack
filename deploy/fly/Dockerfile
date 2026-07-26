# Static-site image: nginx-alpine serving the love.js web bundle.
# Built from repo root: `docker build -f deploy/fly/Dockerfile .`
# Pin the multi-architecture image index so Docker, Fly, and rootless Podman all
# resolve the same trusted base without relying on a short-name registry.
FROM docker.io/library/nginx:1.31.3-alpine@sha256:4a73073bd557c65b759505da037898b61f1be6cbcc3c2c3aeac22d2a470c1752
COPY deploy/fly/nginx.conf /etc/nginx/conf.d/default.conf
COPY dist/web/ /usr/share/nginx/html/
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
