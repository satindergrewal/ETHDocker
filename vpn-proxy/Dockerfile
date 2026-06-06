FROM ubuntu:latest
RUN apt-get update && apt-get install -y --no-install-recommends microsocks && rm -rf /var/lib/apt/lists/*
EXPOSE 1080
CMD ["microsocks", "-i", "0.0.0.0", "-p", "1080"]
