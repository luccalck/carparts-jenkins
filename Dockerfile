FROM node:24-bookworm-slim
WORKDIR /app
ARG COMMIT_SHA=local
ENV NODE_ENV=production PORT=3000 COMMIT_SHA=$COMMIT_SHA
LABEL org.opencontainers.image.revision=$COMMIT_SHA
COPY --chown=node:node src ./src
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s CMD node -e "fetch('http://127.0.0.1:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "src/server.mjs"]
