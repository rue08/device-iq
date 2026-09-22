FROM node:22-slim

# openssl: Prisma's engines need it on slim images.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates openssl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Full install, not --omit=dev: the prisma CLI (a devDependency) is needed
# at container start for `prisma migrate deploy`.
COPY package.json package-lock.json ./
RUN npm ci

COPY prisma.config.js ./
COPY prisma ./prisma
COPY src ./src

# generate only reads the schema, the URL is a placeholder it never connects to.
RUN DATABASE_URL="postgresql://x:x@localhost:5432/x" npx prisma generate

ENV NODE_ENV=production
USER node
EXPOSE 4000

CMD ["sh", "-c", "npx prisma migrate deploy && node src/index.js"]
