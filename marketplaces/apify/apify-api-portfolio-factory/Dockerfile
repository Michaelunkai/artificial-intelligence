FROM apify/actor-node:22

COPY package*.json ./
RUN npm ci --omit=dev

COPY dist ./dist
COPY .actor ./.actor

CMD ["node", "dist/src/main.js"]
