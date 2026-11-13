# Utpost API. Byggs från repots ROT (context: . i compose.yaml, eller `docker build -f api/Dockerfile .`)
# eftersom api/ beror på workspace-paketet shared/ och lockfilen ligger i roten.
FROM node:22-alpine

WORKDIR /app

# Först bara paketfilerna. Det här lagret ändras sällan, så npm ci cachas mellan byggen
# och körs bara om när beroendena ändrats – inte varje gång en rad kod ändras.
COPY package.json package-lock.json ./
COPY shared/package.json shared/
COPY api/package.json api/
RUN npm ci --workspace=api --omit=dev
# M8 (Trivy image): npm behövs för att installera, inte för att köra. Basimagen node:22-alpine skickar med
# npm och dess egna beroenden (pacote, sigstore, brace-expansion …) – sårbarheter i dem är fynd i VÅR image
# fast de aldrig står i vår lockfil. API:et startas med `node`, så npm tas bort ur den färdiga imagen.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx

# Sedan koden. Ändras ofta, ligger därför sist.
COPY shared/ shared/
COPY api/ api/

WORKDIR /app/api
EXPOSE 4000

# M8 (A02, Trivy DS-0002): processen kör inte som root. node-imagen har användaren `node` färdig.
# Allt är redan kopierat och installerat ovanför – node behöver bara läsa.
USER node

# M6: commiten imagen byggdes från. Pipelinen skickar in den (build-args), lokalt blir det "dev".
# Syns i /api/health som `sha` – det är så deploysteget vet att molnet kör rätt version.
ARG GIT_SHA=dev
ENV GIT_SHA=$GIT_SHA

# Node 22.18+ kör routes/guides.ts direkt – inget byggsteg behövs.
# boot.js: väntar på databasen och seedar om SEED_ON_START=1 (staging i molnet), startar sedan index.js.
CMD ["node", "src/boot.js"]
