# Stage 1: Build the Flutter web application
FROM debian:latest AS build-env

# Install required dependencies
RUN apt-get update && apt-get install -y curl git unzip ca-certificates

# Define Flutter version and paths (Updated to 3.47.7 to support Dart 3.13+)
ARG FLUTTER_VERSION=3.47.7
ENV FLUTTER_HOME=/usr/local/flutter
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}"

# Clone the Flutter repository and configure safe directory
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git ${FLUTTER_HOME}
RUN git config --global --add safe.directory ${FLUTTER_HOME}

# Set the working directory and copy project files
WORKDIR /app
COPY . .

# Fetch packages and compile the web app
RUN flutter pub get
RUN flutter build web

# Stage 2: Serve the application using Nginx
FROM nginx:alpine

# Copy the compiled build output from the first stage to Nginx
COPY --from=build-env /app/build/web /usr/share/nginx/html

# Expose port 80
EXPOSE 80

# Start the Nginx server
CMD ["nginx", "-g", "daemon off;"]