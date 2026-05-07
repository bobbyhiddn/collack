# Static-site image: nginx-alpine serving the love.js web bundle.
# Built from repo root: `docker build -f deploy/fly/Dockerfile .`
FROM nginx:alpine
COPY deploy/fly/nginx.conf /etc/nginx/conf.d/default.conf
COPY dist/web/ /usr/share/nginx/html/
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
