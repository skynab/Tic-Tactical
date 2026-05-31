# Single-stage Node 20 image — small enough for free tiers, big enough that
# you don't fight bare-bones Alpine quirks. The relay has no native deps.
FROM node:20-slim

WORKDIR /app

# Install deps first so Docker caches the layer when only server.js changes.
COPY package.json ./
RUN npm install --omit=dev

COPY server.js ./

# Most platforms inject PORT via env. Default to 8080 for local runs.
ENV PORT=8080
EXPOSE 8080

CMD ["node", "server.js"]
