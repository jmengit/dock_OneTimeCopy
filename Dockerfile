# One-Time Copy Docker Container
FROM alpine:3.19

# Install required packages
RUN apk add --no-cache bash

# Create directories
RUN mkdir -p /input /output /data

# Copy the sync script
COPY sync.sh /usr/local/bin/sync.sh
RUN chmod +x /usr/local/bin/sync.sh

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/sync.sh"]
