FROM node:22-alpine
RUN apk add --no-cache wget
WORKDIR /app
COPY package*.json ./
RUN npm ci --production
COPY . .
EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD wget -qO- http://localhost:4000/api/health || exit 1
CMD ["node", "server.js"]
